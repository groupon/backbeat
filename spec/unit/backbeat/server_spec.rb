require "spec_helper"

describe Backbeat::Server do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  class MockScheduler
    def self.call(event, node)
      event.call(node.name + "_called")
    end
  end

  class MockEvent
    def self.call(node)
      node
    end
  end

  context ".fire_event" do
    it "schedules the event with the node" do
      expect(Backbeat::Server.fire_event(MockEvent, node, MockScheduler)).to eq("test_node_called")
    end

    it "noops if node is deactivated" do
      node.current_server_status = "deactivated"

      expect(MockScheduler).to_not receive(:call)

      Backbeat::Server.fire_event(MockEvent, node, MockScheduler)
    end
  end

  context ".create_workflow" do
    it "defaults the migrated field to true" do
      params = {
        workflow_type: "New Workflow",
        subject: "a subject",
        decider: "a decider"
      }

      workflow = Backbeat::Server.create_workflow(params, user)

      expect(workflow.migrated?).to eq(true)
    end

    it "returns workflow if race condition occurs" do
      original_call = Backbeat::Workflow.method(:where)
      lookup_count = 0
      allow(Backbeat::Workflow).to receive(:where) do |*args|
        lookup_count += 1
        if lookup_count == 1
          # Simulates race condition of creation after lookup
          FactoryGirl.create(:workflow_with_node, name: "UniqueName", decider: "Decider", subject: "Subject", user: user)
          []
        else
          original_call.call(*args)
        end
      end

      params = { workflow_type: "UniqueName", subject: "Subject", decider: "Decider" }
      workflow = Backbeat::Server.create_workflow(params, user)
      expect(lookup_count).to eq(2)
      expect(workflow.name).to eq("UniqueName")
    end

    it "does not return another users workflow if the subject is the same" do
      params = { workflow_type: "UniqueName", subject: "Subject", decider: "Decider" }
      user2 = FactoryGirl.create(:user)
      workflow1 = Backbeat::Server.create_workflow(params, user)
      workflow2 = Backbeat::Server.create_workflow(params, user2)

      expect(workflow1).to_not eq(workflow2)
    end
  end

  context ".signal" do
    let(:params) {{
      name: "New Signal",
      options: {}
    }}

    it "raises an error if the workflow is complete" do
      workflow.complete!

      expect { Backbeat::Server.signal(workflow, {}) }.to raise_error Backbeat::WorkflowComplete
    end

    it "creates the node and details in transactions" do
      expect(Backbeat::ClientNodeDetail).to receive(:create!).and_raise(StandardError)
      expect{ Backbeat::Server.signal(workflow, params) }.to raise_error
      expect(Backbeat::Node.count).to eq(1)
    end

    it "adds the signal node to the workflow" do
      signal = Backbeat::Server.signal(workflow, params)

      expect(signal.parent).to eq(workflow)
    end

    it "sets the signal to ready" do
      signal = Backbeat::Server.signal(workflow, params)

      expect(signal.current_server_status).to eq("ready")
      expect(signal.current_client_status).to eq("ready")
    end

    it "sets the legacy type to decision" do
      signal = Backbeat::Server.signal(workflow, params)

      expect(signal.legacy_type).to eq("decision")
    end
  end

  context ".resume_workflow" do

    it "un-pauses the workflow" do
      workflow.pause!

      Backbeat::Server.resume_workflow(workflow)

      expect(workflow.paused?).to eq(false)
    end

    it "starts any paused nodes on the workflow" do
      node.update_attributes(current_server_status: :paused)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node)

      Backbeat::Server.resume_workflow(workflow)

      expect(node.reload.current_server_status).to eq("started")
    end
  end
end

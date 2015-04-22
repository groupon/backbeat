require "spec_helper"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
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
      expect(V2::Server.fire_event(MockEvent, node, MockScheduler)).to eq(true)
    end

    it "noops if node is deactivated" do
      node.current_server_status = "deactivated"

      expect(MockScheduler).to_not receive(:call)

      V2::Server.fire_event(MockEvent, node, MockScheduler)
    end
  end

  context ".create_workflow" do
    it "defaults the migrated field to true" do
      params = {
        workflow_type: "New Workflow",
        subject: "a subject",
        decider: "a decider"
      }

      workflow = V2::Server.create_workflow(params, user)

      expect(workflow.migrated?).to eq(true)
    end
  end

  context ".signal" do
    let(:params) {{
      name: "New Signal",
      options: {}
    }}

    it "raises an error if the workflow is complete" do
      workflow.complete!

      expect { V2::Server.signal(workflow, {}) }.to raise_error V2::WorkflowComplete
    end

    it "creates the node and details in transactions" do
      expect(V2::ClientNodeDetail).to receive(:create!).and_raise(StandardError)
      expect{ V2::Server.signal(workflow, params) }.to raise_error
      expect(V2::Node.count).to eq(1)
    end

    it "adds the signal node to the workflow" do
      signal = V2::Server.signal(workflow, params)

      expect(signal.parent).to eq(workflow)
    end

    it "sets the signal to ready" do
      signal = V2::Server.signal(workflow, params)

      expect(signal.current_server_status).to eq("ready")
      expect(signal.current_client_status).to eq("ready")
    end

    it "sets the legacy type to decision" do
      signal = V2::Server.signal(workflow, params)

      expect(signal.legacy_type).to eq("decision")
    end
  end
end

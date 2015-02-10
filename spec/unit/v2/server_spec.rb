require "spec_helper"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  class MockScheduler
    def self.schedule(event, node)
      event.call(node.to_s + "_called")
    end
  end

  class MockEvent
    def self.call(node)
      node
    end
  end

  context "fire_event" do
    it "schedules the event with the node" do
      expect(V2::Server.fire_event(MockEvent, :node, MockScheduler)).to eq("node_called")
    end

    it "defaults to the NowScheduler" do
      expect(V2::Server.fire_event(MockEvent, :node)).to eq(:node)
    end
  end

  context "server_error" do
    it "schedules the task with a delay with one less retry" do
      Timecop.freeze

      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(:event, node, Time.now + 30.seconds, 1)

      V2::Server.server_error(:event, node, server_retries_remaining: 2)
    end

    it "marks the node as errored if server_retries_remaining does not exists" do
      expect(V2::Client).to receive(:notify_of).with(node, "error", nil)

      V2::Server.server_error(:event, node)

      expect(node.current_server_status).to eq("errored")
    end

    it "notifies the client if there are no remaining retries" do
      expect(V2::Client).to receive(:notify_of).with(node, "error", "Server Error")

      V2::Server.server_error(:event, node, server_retries_remaining: 0, error: "Server Error")
    end
  end
end

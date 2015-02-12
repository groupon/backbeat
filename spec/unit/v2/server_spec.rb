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

  context "fire_event" do
    it "schedules the event with the node" do
      expect(V2::Server.fire_event(MockEvent, node, MockScheduler)).to eq("#{node.name}_called")
    end

    it "noops if node is deactivated" do
      node.current_server_status = "deactivated"

      expect(MockScheduler).to_not receive(:call)

      V2::Server.fire_event(MockEvent, node, MockScheduler)
    end
  end
end

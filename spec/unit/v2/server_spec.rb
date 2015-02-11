require "spec_helper"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  class MockScheduler
    def self.call(event, node)
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
  end
end

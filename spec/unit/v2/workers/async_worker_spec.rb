require "spec_helper"

describe V2::Workers::AsyncWorker, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "async_event" do
    it "sends a method to the processor" do
      expect(V2::Processors).to receive(:perform).with(:children_ready, node, server_retries_remaining: 4)
      V2::Workers::AsyncWorker.async_event(node, :children_ready)
      V2::Workers::AsyncWorker.drain
    end
  end
end

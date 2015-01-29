require "spec_helper"

describe V2::Workers::AsyncWorker, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.nodes.first }

  it { should be_retryable 4 }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "async_event" do
    it "sends a method to the processor" do
      expect(V2::Processors).to receive(:children_ready).with(node)
      V2::Workers::AsyncWorker.async_event(node, :children_ready)
      V2::Workers::AsyncWorker.drain
    end

    it "sends a client error event when out of retries" do
      V2::Workers::AsyncWorker.sidekiq_retries_exhausted_block.call({'args' => ["V2::Node", node.id, "children_ready"]})
      expect(node.reload.current_client_status).to eq("errored")
    end
  end
end

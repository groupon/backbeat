require "spec_helper"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.nodes.first }

  context "client_error" do
    it "marks the status as errored" do
      V2::Server.fire_event(V2::Server::ClientError, node)
      expect(node.current_client_status).to eq("errored")
    end

    context "with remaining retries" do
      it "fires a retry with backoff event" do
        allow(V2::Server).to receive(:fire_event).with(
          V2::Server::ClientError,
          node
        ).and_call_original
        expect(V2::Server).to receive(:fire_event).with(V2::Server::RetryNodeWithBackoff, node)
        V2::Server.fire_event(V2::Server::ClientError, node)
      end

      it "decrements the retry count" do
        V2::Server.fire_event(V2::Server::ClientError, node)
        expect(node.node_detail.retries_remaining).to eq(3)
      end
    end

    context "with no remaining retries" do
      it "does not retry" do
        node.node_detail.update_attributes(retries_remaining: 0)
        allow(V2::Server).to receive(:fire_event).with(
          V2::Server::ClientError,
          node
        ).and_call_original
        expect(V2::Server).to_not receive(:fire_event).with(V2::Server::RetryNodeWithBackoff, node)
        V2::Server.fire_event(V2::Server::ClientError, node)
      end
    end
  end

  context "retry_node" do
    context "with backoff" do
      it "schedules the retry with the node retry interval" do
        expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
          node,
          :retry_node,
          node.node_detail.retry_interval
        )
        V2::Server.fire_event(V2::Server::RetryNodeWithBackoff, node)
        V2::Workers::AsyncWorker.drain
      end
    end

    it "marks the server status as retrying" do
      allow(V2::Server).to receive(:fire_event).with(
        V2::Server::RetryNode,
        node
      ).and_call_original
      allow(V2::Server).to receive(:fire_event).with(V2::Server::StartNode, node)
      V2::Server.fire_event(V2::Server::RetryNode, node)
      V2::Workers::AsyncWorker.drain
      expect(node.reload.current_server_status).to eq("retrying")
    end
  end
end

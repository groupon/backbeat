require "spec_helper"
require "webmock/rspec"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.nodes.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  def add_node(parent_node, mode, server_status = :pending)
    FactoryGirl.create(
      :v2_node,
      parent: parent_node,
      workflow: workflow,
      user: user,
      mode: mode,
      current_server_status: server_status,
      current_client_status: :pending
    )
  end

  context "start_node" do
    it "schedules a timed node" do
      Timecop.freeze
      node.update_attributes(fires_at: Time.now + 10.minutes)
      V2::Server.fire_event(V2::Server::StartNode, node)
      jobs = V2::Workers::AsyncWorker.jobs
      expect(jobs.count).to eq(1)
      expect(jobs.first["at"]).to eq(Time.now.to_f + 10.minutes.to_f)
    end
  end

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
      before { node.node_detail.update_attributes(retries_remaining: 0) }

      it "does not retry" do
        allow(V2::Server).to receive(:fire_event).with(
          V2::Server::ClientError,
          node
        ).and_call_original
        expect(V2::Server).to_not receive(:fire_event).with(V2::Server::RetryNodeWithBackoff, node)
        V2::Server.fire_event(V2::Server::ClientError, node)
      end

      it "notifies the client" do
        V2::Server.fire_event(V2::Server::ClientError, node)
        expect(WebMock).to have_requested(:post, "http://backbeat-client:9000/notifications")
      end
    end
  end

  context "retry_node" do
    before do
      node.update_attributes(
        current_server_status: :errored,
        current_client_status: :errored
      )
    end

    context "with backoff" do
      it "schedules the retry with the node retry interval" do
        Timecop.freeze
        expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
          node,
          :retry_node,
          Time.now + node.node_detail.retry_interval.minutes
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

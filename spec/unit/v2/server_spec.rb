require "spec_helper"
require "webmock/rspec"

describe V2::Server, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  def add_node(parent_node, mode, server_status = :pending)
    FactoryGirl.create(
      :v2_node,
      parent: parent_node,
      workflow_id: parent_node.workflow_id,
      user: user,
      mode: mode,
      fires_at: Time.now,
      current_server_status: server_status,
      current_client_status: :pending
    )
  end

  context "perform" do
    it "logs the node, method name, and args" do
      expect(Instrument).to receive(:instrument).with(node, :mark_children_ready, { message: "Message" })
      V2::Processors.perform(:mark_children_ready, node, { message: "Message" })
    end

    it "calls the processor method with the node" do
      expect(V2::Processors).to receive(:mark_children_ready)
      V2::Processors.perform(:mark_children_ready, node)
    end

    it "fires server error event when an error is raised" do
      error = StandardError.new
      expect(V2::Processors).to receive(:mark_children_ready).with(node) do
        raise error
      end
      expect(V2::Server).to receive(:server_error).with(
        node,
        { error: error, method: :mark_children_ready, message: "message"}
      )
      expect { V2::Processors.perform(:mark_children_ready, node, { message: "message" }) }.to raise_error(error)
    end
  end

  context "start_node" do
    before do
      node.update_attributes(current_server_status: :started)
    end

    it "schedules a timed node" do
      Timecop.freeze
      node.update_attributes(fires_at: Time.now + 10.minutes)
      V2::Server.fire_event(V2::Server::StartNode, node)
      jobs = V2::Workers::AsyncWorker.jobs

      expect(jobs.count).to eq(1)
      expect(jobs.first["at"]).to eq(Time.now.to_f + 10.minutes.to_f)
    end

    it "performs client action unless its a flag" do
      expect(V2::Client).to receive(:perform_action).with(node)

      V2::Server.fire_event(V2::Server::StartNode, node)
      V2::Workers::AsyncWorker.drain
    end

    it "performs no client action if a flag" do
      node.node_detail.update_attributes(legacy_type: :flag)
      allow(V2::Server).to receive(:fire_event).with(
        V2::Server::StartNode,
        node
      ).and_call_original

      expect(V2::Server).to receive(:fire_event).with(V2::Server::ClientComplete, node)

      V2::Server.fire_event(V2::Server::StartNode, node)
      V2::Workers::AsyncWorker.drain
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
        expect(WebMock).to have_requested(:post, "http://backbeat-client:9000/notifications").with(
          body: {
            "notification" => {
              "type" => "V2::Node",
              "id" => node.id,
              "name" => node.name,
              "subject" => node.subject,
              "message" => "error"
            },
            "error" => {
              "errorKlass" => "String",
              "message" => "Client Errored"
            }
          }
        )
      end
    end
  end

  context "server_error" do
    it "schedules the task with a delay with one less retry" do
      Timecop.freeze
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(node, :blah, Time.now + 30.seconds, 1)
      V2::Server.server_error(node, { method: :blah, server_retries_remaining: 2})
    end

    it "marks the node as errored if server_retries_remaining does not exists" do
      V2::Server.server_error(node, { method: :blah })
      expect(node.current_server_status).to eq("errored")
    end

    it "notifies the client if there are no remaining retries" do
      expect(V2::Client).to receive(:notify_of).with(node, "error", "Server Error")
      V2::Server.server_error(node, { method: :blah, server_retries_remaining: 0, error: "Server Error"})
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
      allow(V2::Server).to receive(:fire_event).with(V2::Server::ScheduleNextNode, node.parent)
      V2::Server.fire_event(V2::Server::RetryNode, node)
      V2::Workers::AsyncWorker.drain
      expect(node.status_changes.first.to_status).to eq("retrying")
      expect(node.status_changes.second.to_status).to eq("ready")
    end
  end
end

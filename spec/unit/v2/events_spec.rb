require "spec_helper"
require "webmock/rspec"

describe V2::Events, v2: true do
  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "MarkChildrenReady" do
    before do
      node.update_attributes(
        current_server_status: :pending,
        current_client_status: :pending
      )
    end

    it "marks all children ready" do
      V2::Events::MarkChildrenReady.call(workflow)

      node.reload
      expect(node.current_server_status).to eq("ready")
      expect(node.current_client_status).to eq("ready")
    end

    it "calls ChildrenReady" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::ChildrenReady, workflow)

      V2::Events::MarkChildrenReady.call(workflow)
    end
  end

  context "ChildrenReady" do
    it "calls ScheduleNextNode if all children are ready" do
      node.update_attributes(current_server_status: :ready)

      expect(V2::Server).to receive(:fire_event).with(V2::Events::ScheduleNextNode, workflow)

      V2::Events::ChildrenReady.call(workflow)
    end

    it "does not call ScheduleNextNode if children are not ready" do
      node.update_attributes(current_server_status: :pending)

      expect(V2::Server).to_not receive(:fire_event).with(V2::Events::ScheduleNextNode, workflow)

      V2::Events::ChildrenReady.call(workflow)
    end
  end

  context "ScheduleNextNode" do
    let(:node_2) {
      FactoryGirl.create(
        :v2_node,
        mode: :blocking,
        workflow_id: workflow.id,
        user_id: user.id
      )
    }

    it "fires NodeComplete if all children are complete" do
      node.update_attributes(current_server_status: :complete)

      expect(V2::Server).to receive(:fire_event).with(V2::Events::NodeComplete, workflow)

      V2::Events::ScheduleNextNode.call(workflow)
    end

    it "starts the first ready child node" do
      node.update_attributes(current_server_status: :ready)

      expect(V2::Server).to receive(:fire_event).with(V2::Events::StartNode, node)

      V2::Events::ScheduleNextNode.call(workflow)
    end

    it "starts more nodes if the first ready node is non-blocking" do
      node.update_attributes(current_server_status: :ready, mode: :non_blocking)
      node_2.update_attributes(current_server_status: :ready)

      expect(V2::Server).to receive(:fire_event).with(V2::Events::StartNode, node)
      expect(V2::Server).to receive(:fire_event).with(V2::Events::StartNode, node_2)

      V2::Events::ScheduleNextNode.call(workflow)
    end

    it "does not start more nodes if the first ready node is blocking" do
      node.update_attributes(current_server_status: :ready, mode: :blocking)
      node_2.update_attributes(current_server_status: :ready)

      expect(V2::Server).to receive(:fire_event).with(V2::Events::StartNode, node)
      expect(V2::Server).to_not receive(:fire_event).with(V2::Events::StartNode, node_2)

      V2::Events::ScheduleNextNode.call(workflow)
    end
  end

  context "StartNode" do
    before do
      node.update_attributes(current_server_status: :started)
    end

    it "performs client action unless its a flag" do
      expect(V2::Client).to receive(:perform_action).with(node)

      V2::Events::StartNode.call(node)
    end

    it "performs no client action if a flag" do
      node.node_detail.update_attributes(legacy_type: :flag)

      expect(V2::Server).to receive(:fire_event).with(V2::Events::ClientComplete, node)

      V2::Events::StartNode.call(node)
    end
  end

  context "ClientProcessing" do
    before do
      node.update_attributes(current_client_status: :received)
    end

    it "updates the client status to processing" do
      V2::Events::ClientProcessing.call(node)

      expect(node.current_client_status).to eq("processing")
    end
  end

  context "ClientComplete" do
    before do
      node.update_attributes(
        current_client_status: :processing,
        current_server_status: :sent_to_client
      )
    end

    it "updates the status to complete and fires MarkChildrenReady" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::MarkChildrenReady, node)

      V2::Events::ClientComplete.call(node)

      expect(node.current_server_status).to eq("processing_children")
      expect(node.current_client_status).to eq("complete")
    end
  end

  context "NodeComplete" do
    before do
      node.update_attributes(current_server_status: :processing_children)
    end

    it "does nothing if the node does not have a parent" do
      expect(V2::StateManager).to_not receive(:call)

      V2::Events::NodeComplete.call(workflow)
    end

    it "updates the state to complete and fires ScheduleNext Node if the node has a parent" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::ScheduleNextNode, workflow)

      V2::Events::NodeComplete.call(node)

      expect(node.current_server_status).to eq("complete")
    end
  end

  context "ClientError" do
    it "marks the status as errored" do
      V2::Events::ClientError.call(node)
      expect(node.current_client_status).to eq("errored")
    end

    context "with remaining retries" do
      it "fires a retry with backoff event" do
        expect(V2::Server).to receive(:fire_event).with(V2::Events::RetryNode, node)
        V2::Events::ClientError.call(node)
      end

      it "decrements the retry count" do
        V2::Events::ClientError.call(node)
        expect(node.node_detail.retries_remaining).to eq(3)
      end
    end

    context "with no remaining retries" do
      before do
        node.node_detail.update_attributes(retries_remaining: 0)
      end

      it "does not retry" do
        expect(V2::Server).to_not receive(:fire_event).with(V2::Events::RetryNode, node)

        V2::Events::ClientError.call(node)
      end

      it "notifies the client" do
        V2::Events::ClientError.call(node)
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

  context "RetryNode" do
    before do
      node.update_attributes(
        current_server_status: :sent_to_client,
        current_client_status: :errored
      )
    end

    it "marks the server status as retrying, then ready" do
      V2::Events::RetryNode.call(node)
      expect(node.status_changes.first.attributes).to include({"from_status" => "errored", "to_status" => "ready", "status_type" => "current_client_status"})
      expect(node.status_changes.second.attributes).to include({"from_status" => "sent_to_client", "to_status" => "retrying", "status_type" => "current_server_status"})
      expect(node.status_changes.third.attributes).to include({"from_status" => "retrying", "to_status" => "ready", "status_type" => "current_server_status"})
    end

    it "fires the ScheduleNextNode event with the parent" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::ScheduleNextNode, workflow)
      V2::Events::RetryNode.call(node)
    end
  end

  context "DeactivatePreviousNodes" do
    it "marks all children up to the provided node id as deactivated" do
      second_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: node,
        user: user
      )
      third_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: node,
        user: user
      )
      V2::Events::DeactivatePreviousNodes.call(second_node)

      expect(node.reload.current_server_status).to eq("deactivated")
      expect(second_node.reload.current_server_status).to eq("pending")
      expect(third_node.reload.current_server_status).to eq("pending")
    end
  end

  context "ResetNode" do
    it "marks all children of the provided node as deactivated" do
      second_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: node,
        user: user
      )
      third_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: node,
        user: user
      )
      V2::Events::ResetNode.call(node)

      expect(node.reload.current_server_status).to eq("pending")
      expect(second_node.reload.current_server_status).to eq("deactivated")
      expect(third_node.reload.current_server_status).to eq("deactivated")
    end
  end
end

# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require "spec_helper"
require "webmock/rspec"

describe Backbeat::Events do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
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
      Backbeat::Events::MarkChildrenReady.call(workflow)

      node.reload
      expect(node.current_server_status).to eq("ready")
      expect(node.current_client_status).to eq("ready")
    end

    it "ignores deactivated children" do
      node.update_attributes(
        current_server_status: :deactivated,
        current_client_status: :complete
      )

      Backbeat::Events::MarkChildrenReady.call(workflow)

      node.reload
      expect(node.current_server_status).to eq("deactivated")
      expect(node.current_client_status).to eq("complete")
    end

    it "calls ScheduleNextNode if all children are ready" do
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ScheduleNextNode, workflow)

      Backbeat::Events::MarkChildrenReady.call(workflow)
    end
  end

  context "ScheduleNextNode" do
    let(:node_2) {
      FactoryGirl.create(
        :node,
        mode: :blocking,
        workflow_id: workflow.id,
        user_id: user.id
      )
    }

    it "fires NodeComplete if all children are complete" do
      node.update_attributes(current_server_status: :complete)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::NodeComplete, workflow)

      Backbeat::Events::ScheduleNextNode.call(workflow)
    end

    it "starts the first ready child node" do
      node.update_attributes(current_server_status: :ready)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node)

      Backbeat::Events::ScheduleNextNode.call(workflow)
    end

    it "starts more nodes if the first ready node is non-blocking" do
      node.update_attributes(current_server_status: :ready, mode: :non_blocking)
      node_2.update_attributes(current_server_status: :ready)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node)
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node_2)

      Backbeat::Events::ScheduleNextNode.call(workflow)
    end

    it "does not start more nodes if the first ready node is blocking" do
      node.update_attributes(current_server_status: :ready, mode: :blocking)
      node_2.update_attributes(current_server_status: :ready)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node)
      expect(Backbeat::Server).to_not receive(:fire_event).with(Backbeat::Events::StartNode, node_2)

      Backbeat::Events::ScheduleNextNode.call(workflow)
    end

    it "resets the child node back to ready if start node cannot be enqueued" do
      node.update_attributes(current_server_status: :ready)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node) do
        raise "Connection Error"
      end

      expect { Backbeat::Events::ScheduleNextNode.call(workflow) }.to raise_error
      expect(node.reload.current_server_status).to eq("ready")
    end

    it "does nothing if another process is already scheduling" do
      node.update_attributes(current_server_status: :ready)
      allow(Backbeat::StateManager).to receive(:transition).and_raise(Backbeat::StaleStatusChange)

      expect { Backbeat::Events::ScheduleNextNode.call(workflow) }.to_not raise_error
    end
  end

  context "StartNode" do
    before do
      node.update_attributes(current_server_status: :started)
      allow(Backbeat::Client).to receive(:perform_action).with(node)
    end

    context "with client action" do
      it "updates the node statuses" do
        allow(Backbeat::Client).to receive(:perform_action).with(node)

        Backbeat::Events::StartNode.call(node)

        expect(node.current_server_status).to eq("sent_to_client")
        expect(node.current_client_status).to eq("received")
      end

      it "touches the node" do
        expect(node).to receive(:touch!)
        Backbeat::Events::StartNode.call(node)
      end

      it "sends the node to the client" do
        expect(Backbeat::Client).to receive(:perform_action).with(node)

        Backbeat::Events::StartNode.call(node)
      end

      it "fires the ClientError event if the client call fails" do
        allow(Backbeat::Client).to receive(:perform_action).with(node) { raise Backbeat::HttpError.new("Failed", {}) }

        expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ClientError, node)

        Backbeat::Events::StartNode.call(node)
      end
    end

    context "without client action" do
      it "updates the node statuses" do
        node.node_detail.update_attributes(legacy_type: :flag)
        allow(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ClientComplete, node)

        Backbeat::Events::StartNode.call(node)

        expect(node.current_server_status).to eq("sent_to_client")
        expect(node.current_client_status).to eq("received")
      end

      it "performs no client action if a flag" do
        node.node_detail.update_attributes(legacy_type: :flag)

        expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ClientComplete, node)

        Backbeat::Events::StartNode.call(node)
      end
    end

    context "paused" do
      it "does not start the node" do
        node.workflow.pause!

        expect(Backbeat::Client).to_not receive(:perform_action)

        Backbeat::Events::StartNode.call(node)
      end

      it "transitions the server status to paused" do
        node.workflow.pause!

        Backbeat::Events::StartNode.call(node)

        expect(node.current_server_status).to eq("paused")
      end
    end
  end

  context "ClientProcessing" do
    before do
      node.update_attributes(current_client_status: :received)
    end

    it "updates the client status to processing" do
      Backbeat::Events::ClientProcessing.call(node)

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

    it "updates the status to complete, marks_complete!, and fires MarkChildrenReady" do
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::MarkChildrenReady, node)
      expect(node).to receive(:mark_complete!)

      Backbeat::Events::ClientComplete.call(node)

      expect(node.current_server_status).to eq("processing_children")
      expect(node.current_client_status).to eq("complete")
    end

    it "rolls back if error occurs" do
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::MarkChildrenReady, node).and_raise "error"
      expect { Backbeat::Events::ClientComplete.call(node) }.to raise_error

      expect(node.current_server_status).to eq("sent_to_client")
      expect(node.current_client_status).to eq("processing")
    end
  end

  context "NodeComplete" do
    before do
      node.update_attributes(current_server_status: :processing_children)
    end

    it "does nothing if the node does not have a parent" do
      expect(Backbeat::StateManager).to_not receive(:transition)

      Backbeat::Events::NodeComplete.call(workflow)
    end

    it "updates the state to complete and fires ScheduleNext Node if the node has a parent" do
      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ScheduleNextNode, workflow)

      Backbeat::Events::NodeComplete.call(node)

      expect(node.current_server_status).to eq("complete")
    end

    it "does not fire ScheduleNextNode if the node is fire_and_forget mode" do
      node.update_attributes(current_server_status: :complete, current_client_status: :complete)
      child_node = FactoryGirl.create(:node, user: user, workflow: workflow, mode: :fire_and_forget)
      child_node.update_attributes(current_server_status: :processing_children)

      expect(Backbeat::Server).to_not receive(:fire_event)

      Backbeat::Events::NodeComplete.call(child_node)
    end

    context "multiple complete events (i.e. two non-blocking child nodes both complete at the same time)" do
      it "does nothing if the node is already complete" do
        node.update_attributes(current_server_status: :complete)

        expect(Backbeat::Server).to_not receive(:fire_event)

        Backbeat::Events::NodeComplete.call(node)

        expect { Backbeat::Events::NodeComplete.call(node) }.to_not raise_error
      end

      it "does nothing if another process completes the node at the same time" do
        node.update_attributes(current_server_status: :processing_children)
        Backbeat::Node.where(id: node.id).update_all(current_server_status: :complete)

        Backbeat::Events::NodeComplete.call(node)

        expect { Backbeat::Events::NodeComplete.call(node) }.to_not raise_error
      end
    end
  end

  context "ServerError" do
    it "marks the server status as errored" do
      Backbeat::Events::ServerError.call(node)
      expect(node.current_server_status).to eq("errored")
    end

    it "notifies the client" do
      error = { message: "Failed" }

      expect(Backbeat::Client).to receive(:notify_of).with(node, "Server Error", error)

      Backbeat::Events::ServerError.new({ error: error }).call(node)
    end
  end

  context "ClientError" do
    before do
      node.update_attributes(current_server_status: :sent_to_client)
    end

    it "marks the status as errored" do
      Backbeat::Events::ClientError.call(node)

      expect(node.current_client_status).to eq("errored")
    end

    context "with remaining retries" do
      it "fires a retry with backoff event" do
        expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::RetryNode, node)

        Backbeat::Events::ClientError.call(node)
      end

      it "decrements the retry count" do
        Backbeat::Events::ClientError.call(node)

        expect(node.node_detail.retries_remaining).to eq(3)
      end

      it "marks the server status as retrying" do
        Backbeat::Events::ClientError.call(node)

        expect(node.current_server_status).to eq("retrying")
      end
    end

    context "with no remaining retries" do
      before do
        node.update_attributes(current_server_status: :sent_to_client)
        node.node_detail.update_attributes(retries_remaining: 0)
      end

      it "does not retry" do
        expect(Backbeat::Server).to_not receive(:fire_event).with(Backbeat::Events::RetryNode, node)

        Backbeat::Events::ClientError.call(node)

        expect(node.current_client_status).to eq("errored")
        expect(node.current_server_status).to eq("retries_exhausted")
      end

      it "notifies the client" do
        error = { message: "Failed" }

        expect(Backbeat::Client).to receive(:notify_of).with(node, "Client Error", error)

        Backbeat::Events::ClientError.new({ error: error }).call(node)
      end
    end
  end

  context "RetryNode" do
    before do
      node.update_attributes(
        current_server_status: :retrying,
        current_client_status: :errored
      )
    end

    it "marks the server status as ready" do
      Backbeat::Events::RetryNode.call(node)

      expect(node.status_changes.first.attributes).to include({
        "from_status" => "errored",
        "to_status" => "ready",
        "status_type" => "current_client_status"
      })
      expect(node.status_changes.second.attributes).to include({
        "from_status" => "retrying",
        "to_status" => "ready",
        "status_type" => "current_server_status"
      })
    end

    it "fires the ScheduleNextNode event with the parent" do
      allow(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ResetNode, node)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ScheduleNextNode, workflow)

      Backbeat::Events::RetryNode.call(node)
    end

    it "resets the node" do
      2.times do
        FactoryGirl.create(
          :node,
          parent: node,
          user: user,
          workflow: workflow,
          current_server_status: :ready,
          current_client_status: :ready,
        )
      end

      Backbeat::Events::RetryNode.call(node)

      expect(node.children.first.current_server_status).to eq("deactivated")
      expect(node.children.second.current_server_status).to eq("deactivated")
    end
  end

  context "DeactivatePreviousNodes" do
    it "marks all children up to the provided node id as deactivated" do
      second_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )
      third_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )
      Backbeat::Events::DeactivatePreviousNodes.call(second_node.reload)

      expect(node.reload.current_server_status).to eq("deactivated")
      expect(second_node.reload.current_server_status).to eq("pending")
      expect(third_node.reload.current_server_status).to eq("pending")
    end
  end

  context "ResetNode" do
    it "marks all children of the provided node as deactivated" do
      second_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )
      third_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )
      Backbeat::Events::ResetNode.call(node)

      expect(node.reload.current_server_status).to eq("pending")
      expect(second_node.reload.current_server_status).to eq("deactivated")
      expect(third_node.reload.current_server_status).to eq("deactivated")
    end
  end

  context "CancelNode" do
    it "deactivates the node and its children then schedules next node on its parent" do
      second_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )
      third_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::ScheduleNextNode, node.parent)

      Backbeat::Events::CancelNode.call(node)

      expect(node.reload.current_server_status).to eq("deactivated")
      expect(second_node.reload.current_server_status).to eq("deactivated")
      expect(third_node.reload.current_server_status).to eq("deactivated")
    end
  end
end

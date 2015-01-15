require "spec_helper"

describe V2::Node, v2: true do

  let(:v2_user) { FactoryGirl.create(:v2_user) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow_with_node, user: v2_user) }
  let(:node) { v2_workflow.nodes.first }

  context "update_status" do
    it "creates a status change when the client status has changed" do
      node.update_status(current_client_status: :errored, current_server_status: :errored)
      client_status, server_status = node.status_changes.order("status_type asc").last(2)
      expect(client_status.to_status).to eq("errored")
      expect(server_status.to_status).to eq("errored")
      expect(client_status.status_type).to eq("current_client_status")
      expect(server_status.status_type).to eq("current_server_status")
    end

    it "raised an error if invalid status change" do
      expect {
        node.update_status(current_client_status: node.current_client_status)
      }.to raise_error(V2::InvalidEventStatusChange)
      expect(node.status_changes.count).to eq(0)
    end
  end

  context "mark_retried!" do
    it "decrements the retries remaining" do
      expect(node.retries_remaining).to eq(4)

      node.mark_retried!

      expect(node.reload.retries_remaining).to eq(3)
    end
  end

  context "started?" do
    it "returns true if nodes server status is started" do
      node.current_server_status = :started
      expect(node.started?).to eq(true)
    end

    it "returns false if server status not started" do
      expect(node.started?).to eq(false)
    end
  end

  context "ready_children" do
    it "returns all child nodes marked as ready" do
      child_node = FactoryGirl.create(
        :v2_node,
        workflow: v2_workflow,
        user: v2_user,
        parent: node,
        current_server_status: :ready
      )
      expect(node.ready_children.count).to eq(1)
      expect(node.ready_children.first).to eq(child_node)
    end
  end

  context "blocking?" do
    it "returns true if the mode is blocking" do
      expect(node.blocking?).to be_true
    end

    it "returns false if the mode is non-blocking" do
      node.mode = :non_blocking
      expect(node.blocking?).to be_false
    end

    it "returns false if the mode is fire_and_forget" do
      node.mode = :fire_and_forget
      expect(node.blocking?).to be_false
    end
  end
end

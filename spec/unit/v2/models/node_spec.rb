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
end

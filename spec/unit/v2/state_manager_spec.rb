require "spec_helper"

describe V2::StateManager, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }
  let(:manager) { V2::StateManager.new(node) }

  it "creates a status change when the client status has changed" do
    manager.update_status(current_client_status: :errored, current_server_status: :errored)
    client_status, server_status = node.status_changes.order("status_type asc").last(2)
    expect(client_status.to_status).to eq("errored")
    expect(server_status.to_status).to eq("errored")
    expect(client_status.status_type).to eq("current_client_status")
    expect(server_status.status_type).to eq("current_server_status")
  end

  it "updates the node attributes" do
    manager.update_status(current_client_status: :received, current_server_status: :ready)

    expect(node.current_client_status).to eq('received')
    expect(node.current_server_status).to eq('ready')
  end

  it "raised an error if invalid status change" do
    expect {
      manager.update_status(current_client_status: node.current_client_status)
    }.to raise_error(V2::InvalidEventStatusChange)
    expect(node.status_changes.count).to eq(0)
  end
end

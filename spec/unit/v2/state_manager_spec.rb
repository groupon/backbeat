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
      manager.update_status(current_server_status: node.current_server_status)
    }.to raise_error(V2::InvalidServerStatusChange)
    expect(node.status_changes.count).to eq(0)
  end

  it "returns the current node status in the exception data" do
    begin
      node.update_attributes(current_client_status: :processing)
      manager.update_status(current_client_status: :processing)
    rescue V2::InvalidClientStatusChange => e
      expect(e.data).to eq({
        current_status: :processing,
        attempted_status: :processing,
        status_type: :current_client_status
      })
    end
  end

  it "creates status changes if the transition is successful" do
    manager.update_status(current_client_status: :received, current_server_status: :ready)

    expect(node.status_changes.count).to eq(2)
  end

  it "does not create an status changes if either validation fails" do
    expect {
      manager.update_status(current_client_status: :received, current_server_status: :complete)
    }.to raise_error

    expect(node.status_changes.count).to eq(0)
  end

  it "no-ops if the node is a workflow" do
    expect(V2::StateManager.call(workflow, current_server_status: :complete)).to be_nil
  end
end

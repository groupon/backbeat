require "spec_helper"

describe V2::Workflow, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow, user: user) }
  let(:node) { v2_workflow.nodes.first }

  context "children_ready_to_start" do
    it "returns a child node that are ready and do not have a previous node running" do
      child_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        user: user,
        current_server_status: :ready
      )
      expect(workflow.children_ready_to_start.count).to eq(1)
      expect(workflow.children_ready_to_start.first).to eq(child_node)
    end

    it "returns no child node if a previous node is not complete" do
      FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        user: user,
        current_server_status: :sent_to_client
      )
      child_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        user: user,
        current_server_status: :ready
      )
      expect(workflow.children_ready_to_start.count).to eq(0)
    end
  end
end

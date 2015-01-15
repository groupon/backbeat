require "spec_helper"

describe V2::Workflow, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { v2_workflow.nodes.first }

  context "ready_children" do
    it "returns all child nodes marked as ready" do
      child_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        user: user,
        current_server_status: :ready
      )
      expect(workflow.ready_children.count).to eq(1)
      expect(workflow.ready_children.first).to eq(child_node)
    end
  end
end

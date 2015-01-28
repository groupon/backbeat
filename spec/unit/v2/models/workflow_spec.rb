require "spec_helper"

describe V2::Workflow, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }

  context "workflow_id" do
    it "returns the id" do
      expect(workflow.workflow_id).to eq(workflow.id)
    end
  end

  context "children" do
    it "returns nodes with the same workflow_id and no parent node" do
      node = workflow.nodes.first
      FactoryGirl.create(
        :v2_node,
        user: user,
        workflow_id: workflow.id,
        parent_id: node.id
      )
      expect(workflow.children.count).to eq(1)
      expect(workflow.children.first).to eq(node)
    end
  end
end

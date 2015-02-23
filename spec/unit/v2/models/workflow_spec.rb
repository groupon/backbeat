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

  context "not_complete_children" do
    it "does not return complete children" do
      not_complete_node = workflow.nodes.first
      FactoryGirl.create(
        :v2_node,
        user: user,
        workflow_id: workflow.id,
        parent: workflow,
        current_server_status: :complete
      )

      expect(workflow.not_complete_children.count).to eq(1)
      expect(workflow.not_complete_children.first.id).to eq(not_complete_node.id)
    end

    it "does not return deactivated children" do
      not_deactivated_node = workflow.nodes.first
      FactoryGirl.create(
        :v2_node,
        user: user,
        workflow_id: workflow.id,
        parent: workflow,
        current_server_status: :deactivated
      )

      expect(workflow.not_complete_children.count).to eq(1)
      expect(workflow.not_complete_children.first.id).to eq(not_deactivated_node.id)
    end
  end

  include Colorize

  context "print_tree" do
    it "prints the tree of the node" do
      output = capture(:stdout) do
        workflow.print_tree
      end

      expect(output).to eq(V2::WorkflowTree.to_string(workflow) + "\n")
    end
  end

  context "complete!" do
    it "sets the complete attribute to true" do
      expect(workflow.complete?).to eq(false)

      workflow.complete!

      expect(workflow.complete?).to eq(true)
    end
  end
end

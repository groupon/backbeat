require "spec_helper"

describe Backbeat::Workflow do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }

  context "workflow_id" do
    it "returns the id" do
      expect(workflow.workflow_id).to eq(workflow.id)
    end
  end

  context "children" do
    it "returns nodes with the same workflow_id and no parent node" do
      node = workflow.nodes.first
      FactoryGirl.create(
        :node,
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
        :node,
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
        :node,
        user: user,
        workflow_id: workflow.id,
        parent: workflow,
        current_server_status: :deactivated
      )

      expect(workflow.not_complete_children.count).to eq(1)
      expect(workflow.not_complete_children.first.id).to eq(not_deactivated_node.id)
    end
  end

  context "destroy" do
    it "destroys the workflow and its children" do
      expect(workflow.children.count).to eq(1)
      workflow.destroy
      expect(Backbeat::Workflow.count).to eq(0)
      expect(Backbeat::Node.count).to eq(0)
    end
  end

  include Backbeat::Colorize

  context "print_tree" do
    it "prints the tree of the node" do
      output = capture(:stdout) do
        workflow.print_tree
      end

      expect(output).to eq(Backbeat::WorkflowTree.to_string(workflow) + "\n")
    end
  end

  context "complete!" do
    it "sets the complete attribute to true" do
      expect(workflow.complete?).to eq(false)

      workflow.complete!

      expect(workflow.complete?).to eq(true)
    end
  end

  context "pause!" do
    it "sets the paused attribute to true" do
      expect(workflow.paused?).to eq(false)

      workflow.pause!

      expect(workflow.paused?).to eq(true)
    end
  end

  context "resume!" do
    it "sets the paused attribute to false" do
      workflow.pause!

      workflow.resume!

      expect(workflow.paused?).to eq(false)
    end
  end
end

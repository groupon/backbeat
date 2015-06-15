require "spec_helper"
require "helper/capture"

describe Backbeat::Node do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  context "workflow_id" do
    it "is set to the parent workflow id" do
      expect(node.workflow_id).to eq(workflow.workflow_id)
    end
  end

  context "parent" do
    it "assigns the parent_id if the parent node is a Node" do
      new_node = FactoryGirl.create(:node, user: user, workflow: workflow)
      node.update_attributes(parent: new_node)
      expect(node.parent_id).to eq(new_node.id)
    end

    it "does not assign the parent_id if the parent node is a Workflow" do
      node.update_attributes(parent: workflow)
      expect(node.parent_id).to be_nil
    end

    it "returns the workflow if there is not a parent node" do
      expect(node.parent).to eq(workflow)
    end

    it "returns the parent node if there is one" do
      new_node = FactoryGirl.create(
        :node,
        user: user,
        workflow: workflow,
        parent: node
      )
      expect(new_node.parent).to eq(node)
    end
  end

  context "mark_retried!" do
    it "decrements the retries remaining" do
      expect(node.retries_remaining).to eq(4)

      node.mark_retried!

      expect(node.reload.retries_remaining).to eq(3)
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

  context "decision?" do
    it "returns true if legacy type is decision" do
      node.legacy_type = "decision"
      expect(node.decision?).to eq(true)
    end

    it "returns false if legacy type is anything else" do
      node.legacy_type = :blah
      expect(node.decision?).to eq(false)
    end
  end

  context "destroy" do
    it "destroys the node and its children" do
      FactoryGirl.create(:node, user: user, workflow: workflow, parent: node)
      expect(Backbeat::Node.count).to eq(2)
      node.destroy
      expect(Backbeat::Node.count).to eq(0)
    end
  end

  include Backbeat::Colorize

  context "print_tree" do
    it "prints the tree of the node" do
      output = Capture.with_out_capture do
        node.print_tree
      end

      expect(output).to eq(Backbeat::WorkflowTree.to_string(node) + "\n")
    end
  end
end

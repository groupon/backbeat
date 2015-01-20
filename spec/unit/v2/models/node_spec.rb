require "spec_helper"

describe V2::Node, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  context "workflow_id" do
    it "is set to the node id if there is not a parent node" do
      expect(workflow.workflow_id).to eq(workflow.id)
    end

    it "is set to the parent workflow id if there is a parent node" do
      expect(node.workflow_id).to eq(workflow.workflow_id)
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
end

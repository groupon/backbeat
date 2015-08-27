require "spec_helper"
require "helper/capture"
require "backbeat/workflow_tree/colorize"

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
      expect(node.blocking?).to be_truthy
    end

    it "returns false if the mode is non-blocking" do
      node.mode = :non_blocking
      expect(node.blocking?).to be_falsey
    end

    it "returns false if the mode is fire_and_forget" do
      node.mode = :fire_and_forget
      expect(node.blocking?).to be_falsey
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

  include Backbeat::WorkflowTree::Colorize

  context "print_tree" do
    it "prints the tree of the node" do
      output = Capture.with_out_capture do
        node.print_tree
      end

      expect(output).to eq(Backbeat::WorkflowTree.to_string(node) + "\n")
    end
  end

  context "touch!" do
    context "client doesn't specify timeout" do
      before do
        node.client_node_detail.update_attributes!(data: {})
      end

      it "uses value from config" do
        node.touch!
        expect(node.node_detail.complete_by).to eq(Time.now + Backbeat::Config.options["default_client_timeout"])
      end

      it "nil if config is not set" do
        allow(Backbeat::Config).to receive(:options).and_return({ "default_client_timeout" => nil })
        node.touch!
        expect(node.node_detail.complete_by).to eq(nil)
      end
    end

    it "client specified time out" do
      node.client_node_detail.update_attributes!(data: {timeout: 100})
      node.touch!
      expect(node.node_detail.complete_by).to eq(Time.now + 100)
    end
  end

  context "links_complete?" do
    let(:node) { FactoryGirl.build(:node) }

    it "returns true if no links exist" do
      allow(Backbeat::Node).to receive(:where).with(link_id: node.id).and_return([])
      expect(node.send(:links_complete?)).to eq(true)
    end

    it "returns true if all links are complete" do
      link_node = FactoryGirl.build(:node, current_server_status: :complete)
      allow(Backbeat::Node).to receive(:where).with(link_id: node.id).and_return([link_node])
      expect(node.send(:links_complete?)).to eq(true)
    end

    it "returns false if some links are not complete" do
      link_node = FactoryGirl.build(:node)
      allow(Backbeat::Node).to receive(:where).with(link_id: node.id).and_return([link_node])
      expect(node.send(:links_complete?)).to eq(false)
    end
  end

  context "nodes_complete?" do
    it "returns true if all_children_complete? and links_complete? are true" do
      allow(node).to receive(:all_children_complete?).and_return(true)
      allow(node).to receive(:links_complete?).and_return(true)
      expect(node.nodes_complete?).to eq(true)
    end

    it "returns false if either all_children_complete? or links_complete? are false" do
      allow(node).to receive(:all_children_complete?).and_return(true)
      allow(node).to receive(:links_complete?).and_return(false)
      expect(node.nodes_complete?).to eq(false)
    end
  end
end

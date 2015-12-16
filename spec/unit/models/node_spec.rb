# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require "spec_helper"
require "support/capture"
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

  context "mark_complete!" do
    it "marks the complete_by attribute as nil" do
      node.node_detail.update_attributes!(complete_by: Time.now)

      node.mark_complete!

      expect(node.node_detail.complete_by).to eq(nil)
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
        expect(node.node_detail.complete_by).to eq(Time.now + Backbeat::Config.options[:client_timeout])
      end

      it "nil if config is not set" do
        allow(Backbeat::Config).to receive(:options).and_return({ "client_timeout" => nil })
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

  context "child_links_complete?" do
    let(:node) { FactoryGirl.build(:node) }

    it "returns true if no links exist" do
      allow(node).to receive(:child_links).and_return([])
      expect(node.send(:child_links_complete?)).to eq(true)
    end

    it "returns true if all links are complete" do
      link_node = FactoryGirl.build(:node, current_server_status: :complete)
      allow(node).to receive(:child_links).and_return([link_node])
      expect(node.send(:child_links_complete?)).to eq(true)
    end

    it "returns false if some links are not complete" do
      link_node = FactoryGirl.build(:node)
      allow(node).to receive(:child_links).and_return([link_node])
      expect(node.send(:child_links_complete?)).to eq(false)
    end
  end

  context "all_children_complete?" do
    it "returns true if direct_children_complete? and links_complete? are true" do
      allow(node).to receive(:direct_children_complete?).and_return(true)
      allow(node).to receive(:child_links_complete?).and_return(true)
      expect(node.all_children_complete?).to eq(true)
    end

    it "returns false if either direct_children_complete? or links_complete? are false" do
      allow(node).to receive(:direct_children_complete?).and_return(true)
      allow(node).to receive(:child_links_complete?).and_return(false)
      expect(node.all_children_complete?).to eq(false)
    end
  end

  context "#perform_client_action?" do
    it "returns true if legacy_type is nil" do
      allow(node).to receive(:legacy_type).and_return(nil)
      expect(node.perform_client_action?).to eq(true)
    end

    it "returns false if legacy_type is flag" do
      allow(node).to receive(:legacy_type).and_return("flag")
      expect(node.perform_client_action?).to eq(false)
    end

    it "returns false if legacy_type is not flag" do
      allow(node).to receive(:legacy_type).and_return("blah")
      expect(node.perform_client_action?).to eq(true)
    end
  end

  context "#decision?" do
    it "returns false if legacy_type is nil" do
      allow(node).to receive(:legacy_type).and_return(nil)
      expect(node.decision?).to eq(false)
    end

    it "returns true if legacy_type is decision" do
      allow(node).to receive(:legacy_type).and_return("decision")
      expect(node.decision?).to eq(true)
    end

    it "returns false if legacy_type is not decision" do
      allow(node).to receive(:legacy_type).and_return("blah")
      expect(node.decision?).to eq(false)
    end
  end
end

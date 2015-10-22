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
require "backbeat/workflow_tree/colorize"
require "helper/capture"

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

  include Backbeat::WorkflowTree::Colorize

  context "print_tree" do
    it "prints the tree of the node" do
      output = Capture.with_out_capture do
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

  context "all_children_complete?" do
    it "returns true if direct_children_complete? is true" do
      allow(workflow).to receive(:direct_children_complete?).and_return(true)
      expect(workflow.all_children_complete?).to eq(true)
    end

   it "returns false if direct_children_complete? is false" do
      allow(workflow).to receive(:direct_children_complete?).and_return(false)
      expect(workflow.all_children_complete?).to eq(false)
    end
  end
end

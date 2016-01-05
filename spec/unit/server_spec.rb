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

describe Backbeat::Server do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  class MockScheduler
    def self.call(event, node)
      event.call(node.name + " called")
    end
  end

  class MockEvent
    def self.call(node)
      node
    end
  end

  context ".fire_event" do
    it "schedules the event with the node" do
      expect(Backbeat::Server.fire_event(MockEvent, node, MockScheduler)).to eq("Test-Node called")
    end

    it "noops if node is deactivated" do
      node.current_server_status = "deactivated"

      expect(MockScheduler).to_not receive(:call)

      Backbeat::Server.fire_event(MockEvent, node, MockScheduler)
    end
  end

  context ".create_workflow" do
    it "defaults the migrated field to true" do
      params = {
        workflow_type: "New Workflow",
        subject: "a subject",
        decider: "a decider"
      }

      workflow = Backbeat::Server.create_workflow(params, user)

      expect(workflow.migrated?).to eq(true)
    end

    it "returns workflow if race condition occurs" do
      original_call = Backbeat::Workflow.method(:where)
      lookup_count = 0
      allow(Backbeat::Workflow).to receive(:where) do |*args|
        lookup_count += 1
        if lookup_count == 1
          # Simulates race condition of creation after lookup
          FactoryGirl.create(:workflow_with_node, name: "UniqueName", decider: "Decider", subject: "Subject", user: user)
          []
        else
          original_call.call(*args)
        end
      end

      params = { workflow_type: "UniqueName", subject: "Subject", decider: "Decider" }
      workflow = Backbeat::Server.create_workflow(params, user)
      expect(lookup_count).to eq(2)
      expect(workflow.name).to eq("UniqueName")
    end

    it "does not return another users workflow if the subject is the same" do
      params = { workflow_type: "UniqueName", subject: "Subject", decider: "Decider" }
      user2 = FactoryGirl.create(:user, name: "User 2")
      workflow1 = Backbeat::Server.create_workflow(params, user)
      workflow2 = Backbeat::Server.create_workflow(params, user2)

      expect(workflow1).to_not eq(workflow2)
    end
  end

  context ".signal" do
    let(:params) {{
      name: "New Signal",
      options: {}
    }}

    it "raises an error if the workflow is complete" do
      workflow.complete!

      expect { Backbeat::Server.signal(workflow, {}) }.to raise_error Backbeat::WorkflowComplete
    end

    it "creates the node and details in transactions" do
      expect(Backbeat::ClientNodeDetail).to receive(:create!).and_raise(StandardError)
      expect{ Backbeat::Server.signal(workflow, params) }.to raise_error
      expect(Backbeat::Node.count).to eq(1)
    end

    it "adds the signal node to the workflow" do
      signal = Backbeat::Server.signal(workflow, params)

      expect(signal.parent).to eq(workflow)
    end

    it "sets the signal to ready" do
      signal = Backbeat::Server.signal(workflow, params)

      expect(signal.current_server_status).to eq("ready")
      expect(signal.current_client_status).to eq("ready")
    end

    it "sets the legacy type to decision" do
      signal = Backbeat::Server.signal(workflow, params)

      expect(signal.legacy_type).to eq("decision")
    end
  end

  context ".resume_workflow" do

    it "un-pauses the workflow" do
      workflow.pause!

      Backbeat::Server.resume_workflow(workflow)

      expect(workflow.paused?).to eq(false)
    end

    it "starts any paused nodes on the workflow" do
      node.update_attributes(current_server_status: :paused)

      expect(Backbeat::Server).to receive(:fire_event).with(Backbeat::Events::StartNode, node)

      Backbeat::Server.resume_workflow(workflow)

      expect(node.reload.current_server_status).to eq("started")
    end
  end
end

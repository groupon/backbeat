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

describe Backbeat::StateManager do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }
  let(:manager) { Backbeat::StateManager.new(node) }

  it "creates a status change when the client status has changed" do
    manager.transition(current_client_status: :errored, current_server_status: :errored)
    client_status, server_status = node.status_changes.order("status_type asc").last(2)
    expect(client_status.to_status).to eq("errored")
    expect(server_status.to_status).to eq("errored")
    expect(client_status.status_type).to eq("current_client_status")
    expect(server_status.status_type).to eq("current_server_status")
  end

  it "updates the node attributes" do
    manager.transition(current_client_status: :received, current_server_status: :ready)

    expect(node.current_client_status).to eq('received')
    expect(node.current_server_status).to eq('ready')
  end

  it "raised an error if invalid status change" do
    expect {
      manager.transition(current_server_status: node.current_server_status)
    }.to raise_error(Backbeat::InvalidServerStatusChange)

    expect(node.status_changes.count).to eq(0)
  end

  it "returns exception data for invalid client status change" do
    node.update_attributes(current_client_status: :processing)
    error = nil

    begin
      manager.transition(current_client_status: :processing)
    rescue Backbeat::InvalidClientStatusChange => e
      error = e
    end

    expect(error.data).to eq({
      current_status: :processing,
      attempted_status: :processing
    })
  end

  it "creates status changes if the transition is successful" do
    manager.transition(current_client_status: :received, current_server_status: :ready)

    expect(node.status_changes.count).to eq(2)
  end

  it "creates status changes with a response" do
    node.update_attributes(current_client_status: :processing)
    client_response = { "error" => nil, "result" => 100 }
    manager = Backbeat::StateManager.new(node, client_response)
    manager.transition({ current_client_status: :complete })

    expect(node.status_changes.last.response).to eq(client_response)
  end

  it "does not create an status changes if either validation fails" do
    expect {
      manager.transition(current_client_status: :received, current_server_status: :complete)
    }.to raise_error

    expect(node.status_changes.count).to eq(0)
  end

  it "raises an error if the status change is stale" do
    Backbeat::Node.where(id: node.id).update_all(current_client_status: :received)

    expect { manager.transition(current_client_status: :received) }.to raise_error(Backbeat::StaleStatusChange)
  end

  it "no-ops if the node is a workflow" do
    expect(Backbeat::StateManager.transition(workflow, current_server_status: :complete)).to be_nil
  end

  context "with_rollback" do
    it "rolls back to the starting status if error occurs" do
      expect {
        Backbeat::StateManager.new(node).with_rollback do |state|
          state.transition(current_client_status: :received, current_server_status: :ready)
          raise "random error"
        end
      }.to raise_error

      expect(node.status_changes.count).to eq(4)
      expect(node.current_server_status).to eq("pending")
      expect(node.current_client_status).to eq("ready")
    end

    it "rolls back to the provided status if error occurs" do
      expect {
        Backbeat::StateManager.new(node).with_rollback({ current_server_status: :ready }) do |state|
          raise "random error"
        end
      }.to raise_error

      expect(node.status_changes.count).to eq(2)
      expect(node.current_server_status).to eq("ready")
      expect(node.current_client_status).to eq("ready")
    end

    it "does not add status changes when state transition error occurs" do
      expect {
        Backbeat::StateManager.new(node).with_rollback do |state|
          state.transition(current_client_status: :ready, current_server_status: :pending)
          1 + 1
        end
      }.to raise_error(Backbeat::InvalidClientStatusChange)

      expect(node.status_changes.count).to eq(0)
      expect(node.current_server_status).to eq("pending")
      expect(node.current_client_status).to eq("ready")
    end
  end
end

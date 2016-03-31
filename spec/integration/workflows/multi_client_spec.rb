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
require "support/request_helper"
require "support/sidekiq_helper"

describe Backbeat, :api_test do
  include RequestHelper

  let(:client_A) { FactoryGirl.create(:user, name: "Client A") }
  let(:client_B) { FactoryGirl.create(:user, name: "Client B", activity_endpoint: 'http://client-a/activity') }
  let(:workflow) { FactoryGirl.create(:workflow, user: client_A) }

  def as_client(client)
    header("Client-Id", client.id)
    header("Authorization", "Token token=\"#{client.auth_token}\"")
    yield
  end

  context "workflow with multiple clients" do
    it "sends an activity created by client A to client B" do
      response = nil

      as_client(client_A) do
        response = post "workflows/#{workflow.id}/signal/test", options: {
          client_data: { method: 'publish', params: [1, 2, 3] },
          client_metadata: { metadata: '456'}
        }
      end

      expect(response.status).to eq(201)

      signal = JSON.parse(response.body)
      signal_node = workflow.children.where(id: signal['id']).first

      WebMock.stub_request(:post, client_A.decision_endpoint).with(
        body: decision_hash(signal_node, {
          current_server_status: :sent_to_client,
          current_client_status: :received
        })
      ).to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      as_client(client_A) do
        response = put "activities/#{signal_node.id}/status/processing"
      end

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity = {
        name: "Other client activity",
        client_id: client_B.id
      }

      as_client(client_A) do
        response = post "activities/#{signal_node.id}/decisions", { "decisions" => [activity] }
        response = put "activities/#{signal_node.id}/status/completed"
      end

      expect(signal_node.children.count).to eq(1)

      client_B_activity = signal_node.children.first

      WebMock.stub_request(:post, client_B.activity_endpoint).with(
        body: activity_hash(client_B_activity, {
          current_server_status: :sent_to_client,
          current_client_status: :received
        })
      ).to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      as_client(client_B) do
        response = put "activities/#{client_B_activity.id}/status/processing"
        response = put "activities/#{client_B_activity.id}/status/completed"
      end

      Backbeat::Workers::AsyncWorker.drain

      expect(client_B_activity.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )

      Backbeat::Workers::AsyncWorker.drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

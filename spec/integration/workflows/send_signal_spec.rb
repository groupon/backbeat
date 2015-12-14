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

require 'spec_helper'
require 'helper/request_helper'

describe Backbeat, :api_test do
  include RequestHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  context "POST /workflows/:id/signal" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post "workflows/#{workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        client_metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      node = workflow.children.where(id: signal['id']).first
      expect(node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(node, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "activities/#{node.id}/status/deciding"
      expect(node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity= FactoryGirl.build(:client_activity_data)
      activity_to_post = { "decisions" => [activity] }
      response = post "activities/#{node.id}/decisions", activity_to_post

      expect(node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(node.reload.children.count).to eq(1)

      response = put "activities/#{node.id}/status/deciding_complete"
      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_node = node.children.first
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "activities/#{activity_node.id}/status/completed"
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

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

  context "modes" do
    it "completes a workflow with blocking, non_blocking and fire_and_forget nodes" do
      response = post "workflows/#{workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      signal_node = workflow.children.where(id: signal['id']).first
      expect(signal_node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(signal_node, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "activities/#{signal_node.id}/status/deciding"

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity_1 = FactoryGirl.build(:client_activity_data).merge(mode: :non_blocking)
      activity_2 = FactoryGirl.build(:client_activity_data)
      activity_3 = FactoryGirl.build(:client_activity_data).merge(mode: :non_blocking)
      activity_4 = FactoryGirl.build(:client_activity_data).merge(mode: :fire_and_forget)

      activities_to_post = { "decisions" => [activity_1, activity_2, activity_3, activity_4] }

      response = post "activities/#{signal_node.id}/decisions", activities_to_post

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.children.count).to eq(4)

      response = put "activities/#{signal_node.id}/status/deciding_complete"

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_nodes = signal_node.children
      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      activity_nodes[0..1].each do |activity_node|
        WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
          .with(:body => activity_hash(activity_node, {current_server_status: :sent_to_client, current_client_status: :received}))
          .to_return(:status => 200, :body => "", :headers => {})
      end

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      put "activities/#{activity_nodes[0].id}/status/completed"
      put "activities/#{activity_nodes[1].id}/status/completed"

      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_nodes[2..3].each do |activity_node|
        WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
          .with(:body => activity_hash(activity_node, {current_server_status: :sent_to_client, current_client_status: :received}))
          .to_return(:status => 200, :body => "", :headers => {})
      end

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      put "activities/#{activity_nodes[2].id}/status/completed"

      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      put "activities/#{activity_nodes[3].id}/status/completed"

      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end

    it "completes a workflow with two signals" do
      response = post "workflows/#{workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        client_metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      signal_node = workflow.children.where(id: signal['id']).first
      expect(signal_node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      response_2 = post "workflows/#{workflow.id}/signal/test_2", options: {
        client_data: { data: '124' },
        client_metadata: { metadata: '457'}
      }

      expect(response_2.status).to eq(201)

      signal_2 = JSON.parse(response_2.body)
      signal_node_2 = workflow.children.where(id: signal_2['id']).first

      expect(signal_node_2.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(signal_node, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "activities/#{signal_node.id}/status/deciding"
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity = FactoryGirl.build(:client_activity_data)
      activities_to_post = { "decisions" => [activity] }
      response = post "activities/#{signal_node.id}/decisions", activities_to_post

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.children.count).to eq(1)

      response = put "activities/#{signal_node.id}/status/deciding_complete"
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_node = signal_node.children.first
      expect(signal_node.children[0].reload.attributes).to include(
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

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(signal_node_2, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "activities/#{signal_node_2.id}/status/deciding"
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity = FactoryGirl.build(:client_activity_data)
      activity_to_post_signal_2 = { "decisions" => [activity] }
      response = post "activities/#{signal_node_2.id}/decisions", activity_to_post_signal_2

      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node_2.reload.children.count).to eq(1)

      response = put "activities/#{signal_node_2.id}/status/deciding_complete"
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_node_signal_2 = signal_node_2.children.first
      expect(activity_node_signal_2.reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node_signal_2, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})
      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node_signal_2.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "activities/#{activity_node_signal_2.id}/status/completed"

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node_signal_2.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

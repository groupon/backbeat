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
require 'support/request_helper'
require 'support/sidekiq_helper'

describe Backbeat, :api_test do
  include RequestHelper
  include SidekiqHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node_running, user: user) }
  let(:activity_node) { workflow.children.first.children.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "client error" do
    it "retries with backoff and then succeeds" do
      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node))
        .to_return(:status => 200, :body => "", :headers => {})

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_node.node_detail.retries_remaining).to eq(4)

      response = put "activities/#{activity_node.id}/status/errored"

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_node.node_detail.retries_remaining).to eq(3)

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
      expect(activity_node.parent.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end

    it "retries full number of retries available and fails" do
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      activity_node.node_detail.update_attributes(retries_remaining: 2)
      expect(activity_node.node_detail.retries_remaining).to eq(2)

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node))
        .to_return(:status => 200, :body => "", :headers => {})

      2.times do |i|
        response = put "activities/#{activity_node.id}/status/errored"

        Backbeat::Workers::AsyncWorker.drain

        expect(activity_node.reload.attributes).to include(
          "current_client_status" => "received",
          "current_server_status" => "sent_to_client"
        )
        expect(activity_node.node_detail.retries_remaining).to eq(1 - i)
      end

      response = put "activities/#{activity_node.id}/status/errored"

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "errored",
        "current_server_status" => "retries_exhausted"
      )

      expect(WebMock).to have_requested(:post, "http://backbeat-client:9000/notifications").with({
        body: {
          "activity" => Backbeat::ActivityPresenter.present(activity_node),
          "notification" => {
            "name" => activity_node.name,
            "message" => "Client Error",
          },
          "error" => {}
        }.to_json
      })
    end

    it "resets the node to handle errors in weird states" do
      node = workflow.children.first
      node.update_attributes(
        current_server_status: :sent_to_client,
        current_client_status: :received
      )

      2.times do
        FactoryGirl.create(
          :node,
          parent: node,
          user: user,
          workflow: workflow,
          current_server_status: :ready,
          current_client_status: :ready,
        )
      end

      allow(Backbeat::Client).to receive(:perform) do |node|
        Backbeat::Server.fire_event(Backbeat::Events::ClientComplete, node)
      end

      put "activities/#{node.id}/status/errored"

      Backbeat::Workers::AsyncWorker.drain
      node.reload

      expect(node.current_server_status).to eq("complete")
      expect(node.current_client_status).to eq("complete")
    end
  end

  context "server error" do
    it "sends a message to the client after a set number of retries fails" do
      Timecop.freeze
      expect(Backbeat::Events::StartNode).to receive(:call).exactly(5).times do
        raise StandardError.new("start node failed")
      end

      Backbeat::Server.fire_event(Backbeat::Events::StartNode, activity_node)

      4.times do
        Timecop.travel(Time.now + 31.seconds)
        soft_drain
        expect(activity_node.current_server_status).to eq("sent_to_client")
      end

      Timecop.travel(Time.now + 31.seconds)
      soft_drain
      expect(activity_node.reload.current_server_status).to eq("errored")
    end
  end
end


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
require 'sidekiq/testing'
require 'helper/request_helper'
require 'helper/sidekiq_helper'

describe Backbeat, :api_test do
  include RequestHelper
  include SidekiqHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
    Sidekiq::Testing.fake!
  end

  context "nodes with fires_at" do
    it "does not run a node with fires_at until time has expired" do
      Timecop.freeze

      signal_node = FactoryGirl.create(
        :node,
        name: "signal with timed node",
        user: user,
        workflow: workflow,
        current_server_status: :processing_children,
        current_client_status: :complete,
      )

      timed_activity_node = FactoryGirl.create(
        :node,
        name: "timed node",
        parent: signal_node,
        fires_at: Time.now + 10.minutes,
        mode: :non_blocking,
        user: user,
        current_server_status: :ready,
        current_client_status: :ready,
        workflow: workflow
      )

      activity_node = FactoryGirl.create(
        :node,
        name: "following timed node",
        parent: signal_node,
        user: user,
        workflow: workflow,
        current_server_status: :ready,
        current_client_status: :ready,
        mode: :blocking
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Server::fire_event(Backbeat::Events::ScheduleNextNode, signal_node)

      soft_drain
      expect(timed_activity_node.reload.current_server_status).to eq("started")

      soft_drain
      expect(activity_node.reload.current_server_status).to eq("sent_to_client")

      put "v2/activities/#{activity_node.id}/status/completed"
      soft_drain
      expect(activity_node.reload.current_server_status).to eq("complete")

      soft_drain
      expect(signal_node.reload.current_server_status).to eq("processing_children")
      expect(timed_activity_node.reload.current_server_status).to eq("started")

      # drains schedule next node on workflow
      soft_drain

      Timecop.travel(Time.now + 11.minutes)

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(timed_activity_node, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      soft_drain

      expect(timed_activity_node.reload.current_server_status).to eq("sent_to_client")
      put "v2/activities/#{timed_activity_node.id}/status/completed"

      soft_drain
      expect(timed_activity_node.reload.current_server_status).to eq("complete")

      soft_drain
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

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
require "helper/request_helper"
require "helper/sidekiq_helper"

describe Backbeat, :api_test do
  include RequestHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  context "Pause Workflow" do
    it "prevents all nodes from running until resumed" do
      response = post "workflows/#{workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        client_metadata: { metadata: '456'}
      }
      signal = JSON.parse(response.body)
      node = workflow.children.where(id: signal['id']).first

      expect(node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      put "workflows/#{workflow.id}/pause"

      Backbeat::Workers::AsyncWorker.drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "paused"
      )

      response = put "workflows/#{workflow.id}/resume"

      expect(response.status).to eq(200)

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(node))
        .to_return(:status => 200, :body => "", :headers => {})

      allow(Backbeat::Client).to receive(:perform_action)

      SidekiqHelper.soft_drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
    end
  end
end


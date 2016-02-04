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

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }
  let(:node) { FactoryGirl.create(:node, user: user, workflow: workflow, current_client_status: :received, current_server_status: :sent_to_client) }
  let(:workflow_to_link) { FactoryGirl.create(:workflow, user: user, subject: {test: :node}) }

  context "linked" do
    it "forces a node to wait to complete until its links complete" do
      response = post "workflows/#{workflow_to_link.id}/signal/test", { options: { parent_link_id: node.id } }

      signal_node = workflow_to_link.nodes.first

      expect(workflow_to_link.nodes.count).to eq(1)
      expect(signal_node.parent_link).to eq(node)
      expect(node.child_links).to eq([signal_node])

      put "activities/#{node.id}/status/completed"

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
       .with(:body => decision_hash(signal_node, {current_server_status: :sent_to_client, current_client_status: :received}))
       .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      put "activities/#{signal_node.id}/status/completed"

      SidekiqHelper.soft_drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )

      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      SidekiqHelper.soft_drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

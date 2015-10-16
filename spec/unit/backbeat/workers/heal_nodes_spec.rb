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

describe Backbeat::Workers::HealNodes do
  context "complete_by expires" do
    let(:start_time) { Time.parse("2015-06-01 00:00:00 UTC") }
    let(:user) { FactoryGirl.create(:user) }
    let(:workflow) { FactoryGirl.create(:workflow, user: user) }
    let(:expired_node) do
      FactoryGirl.create(
        :node,
        name: "expired_node",
        parent: nil,
        user: user,
        current_server_status: :sent_to_client,
        current_client_status: :received,
        workflow: workflow
      )
    end
    let(:non_expired_node) do
      FactoryGirl.create(
        :node,
        name: "non_expired_node",
        parent: nil,
        user: user,
        current_server_status: :sent_to_client,
        current_client_status: :received,
        workflow: workflow
      )
    end
    let(:last_run) { (Time.now - 2 * 60 * 60).to_f }

    it "resends nodes to client that have not heard from the client within the complete_by time" do
      Timecop.freeze(start_time) do
        expired_complete_by = Time.now - 1.minute
        expired_node.client_node_detail.update_attributes!(data: {timeout: 120})
        expired_node.node_detail.update_attributes!(complete_by: expired_complete_by)

        non_expired_complete_by = Time.now + 1.minute
        non_expired_node.client_node_detail.update_attributes!(data: {timeout: 120})
        non_expired_node.node_detail.update_attributes!(complete_by: non_expired_complete_by)

        expect(Backbeat::Client).to receive(:perform_action).with(expired_node)
        expect(Backbeat::Client).to_not receive(:perform_action).with(non_expired_node)
        expect(subject).to receive(:info).with(
          message: "Client did not respond within the specified 'complete_by' time",
          node: expired_node.id,
          complete_by: expired_node.node_detail.complete_by
        ).and_call_original

        subject.perform(last_run)

        # Because we use the error node event, it shares the retry logic which has a delay
        Timecop.travel(Time.now + 1.hour)
        Backbeat::Workers::AsyncWorker.drain

        expired_node.reload
        expect(expired_node.current_server_status).to eq("sent_to_client")
        expect(expired_node.current_client_status).to eq("received")
        expect(expired_node.node_detail.complete_by.to_s).to eq("2015-06-01 01:02:00 UTC")
        expect(expired_node.status_changes.first.response).to eq("Client did not respond within the specified 'complete_by' time")

        non_expired_node.reload
        expect(non_expired_node.current_server_status).to eq("sent_to_client")
        expect(non_expired_node.current_client_status).to eq("received")
        expect(non_expired_node.node_detail.complete_by).to eq(non_expired_complete_by)
      end
    end

    it "logs when node is in unexpected state when complete_by is expired" do
      expired_complete_by = Time.now - 1.minute
      expired_node.update_attributes(current_client_status: :complete, current_server_status: :complete)
      expired_node.node_detail.update_attributes!(complete_by: expired_complete_by)
      expect(subject).to receive(:info).with(
        message: "Node with expired 'complete_by' is not in expected state",
        node: expired_node.id,
        complete_by: expired_node.reload.node_detail.complete_by
      ).and_call_original

      subject.perform(last_run)
    end
  end
end


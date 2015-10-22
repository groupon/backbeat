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
require 'mail'

require_relative '../../../scheduled_jobs/daily_activity_report.rb'

describe ScheduledJobs::DailyActivityReport do
  context "successful report" do
    let(:start_time) { Time.parse("2015-06-01 00:00:00") }
    let(:user) { FactoryGirl.create(:user) }
    let(:fun_workflow) { FactoryGirl.create(:workflow, user: user, name: "fun workflow") }
    let(:bad_workflow) { FactoryGirl.create(:workflow, user: user, name: "bad workflow") }
    let!(:complete_node) do
      FactoryGirl.create(
        :node,
        name: "complete node",
        parent: nil,
        fires_at: start_time - 12.hours,
        updated_at: start_time - 12.hours,
        user: user,
        current_server_status: :complete,
        current_client_status: :complete,
        workflow: fun_workflow
      )
    end
    let!(:inconsistent_node) do
      FactoryGirl.create(
        :node,
        name: "bad node",
        parent: nil,
        fires_at: start_time - 2.days,
        updated_at: start_time - 25.hours,
        user: user,
        current_server_status: :ready,
        current_client_status: :ready,
        workflow: bad_workflow
      )
    end

    before do
      Mail.defaults { delivery_method :test }
    end

    it "builds the workflow data" do
      Timecop.freeze(start_time) do
        expect(subject).to receive(:send_report).with({
          inconsistent: {
            counts: {
              "bad workflow" => { workflow_type_count: 1, node_count: 1 }
            },
            options: {
              lower_bound: Time.parse("2015-04-01 00:00:00"),
              upper_bound: Date.today
            },
            filename: "/tmp/inconsistent_nodes/2015-06-01.txt"
          },
          completed: {
            counts: {
              "fun workflow"=> { workflow_type_count: 1, node_count: 1 }
            },
            options: {
              lower_bound: start_time - 24.hours,
              upper_bound: start_time
            }
          },
          time_elapsed: 0
        })

        subject.perform
      end
    end

    it "calls view generation with correct model" do
      Timecop.freeze(start_time) do
        subject.perform
      end

      email_sent = Mail::TestMailer.deliveries.first
      body = email_sent.to_s

      expect(email_sent.from.first).to eq("alerts-sample@email.com")
      expect(email_sent.to.first).to eq("sample@email.com")
      expect(body).to include("Report finished")
    end

    it "writes inconsistent details to file" do
      Timecop.freeze(start_time) do
        expected_file_contents = {
          inconsistent_node.workflow.id => [inconsistent_node.id]
        }

        allow(subject).to receive(:send_report)
        expect(subject).to receive(:write_to_file).with(expected_file_contents)
        subject.perform
      end
    end
  end
end

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

describe Backbeat::Workers::DailyActivity do
  context "successful report" do
    let(:start_time) { Time.now }
    let(:user) { FactoryGirl.create(:user) }
    let(:fun_workflow) { FactoryGirl.create(:workflow, user: user, name: "fun workflow") }
    let(:bad_workflow) { FactoryGirl.create(:workflow, user: user, name: "bad workflow") }
    let(:untriggered_workflow) { FactoryGirl.create(:workflow, user: user, name: "untriggered workflow") }

    let!(:complete_node) do
      FactoryGirl.create(
        :node,
        name: "complete node",
        parent: nil,
        fires_at: start_time - 13.hours,
        updated_at: start_time - 13.hours,
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
        fires_at: start_time - 15.hours,
        updated_at: start_time - 14.hours,
        user: user,
        current_server_status: :ready,
        current_client_status: :ready,
        workflow: bad_workflow
      )
    end

    let!(:untriggered_fire_and_forget_node) do
      FactoryGirl.create(
        :node,
        name: "stalled node",
        parent: nil,
        fires_at: start_time - 400.days,
        updated_at: start_time - 399.days,
        user: user,
        current_server_status: :ready,
        current_client_status: :ready,
        mode: :fire_and_forget,
        workflow: untriggered_workflow
      )
    end

    before do
      Mail.defaults { delivery_method :test }
    end

    it "builds the workflow data with default options" do
      allow(Backbeat::Config).to receive(:hostname).and_return("somehost")

      Timecop.freeze(start_time) do
        expect(subject).to receive(:send_report) do |arg|
          arg == {
            inconsistent: {
              counts: {
                "bad workflow" => { workflow_type_count: 1, node_count: 1 }
              },
              filename: "/tmp/inconsistent_nodes/#{Date.today.to_s}.json",
              hostname: "somehost"
            },
            completed: {
              counts: {
                "fun workflow"=> { workflow_type_count: 1, node_count: 1 }
              }
            },
            time_elapsed: 0,
            range: {
              completed_upper_bound: start_time,
              completed_lower_bound: start_time - 24.hours,
              inconsistent_upper_bound: start_time - 12.hours,
              inconsistent_lower_bound: start_time - 1.year
             },
            date: start_time.strftime("%m/%d/%Y")
          }
        end

        subject.perform
      end
    end

    it "builds the workflow data with specific options" do
      allow(Backbeat::Config).to receive(:hostname).and_return("somehost")
      allow(Backbeat::Config).to receive(:options).and_return(
        Backbeat::Config.options.merge(reporting: {completed_lower_bound: 23.hours.to_i,
                                                   inconsistent_upper_bound: 3.hours.to_i,
                                                   inconsistent_lower_bound: 4.hours.to_i,
                                                   untriggered_fire_and_forget_upper_bound: 7.hours.to_i}
        ))

      Timecop.freeze(start_time) do
        expect(subject).to receive(:send_report).with({
          inconsistent: {
            counts: {},
            filename: "/tmp/inconsistent_nodes/#{Date.today.to_s}.json",
            hostname: "somehost"
          },
          untriggered_fire_and_forget: {
            counts: {
              "untriggered workflow" => { workflow_type_count: 1, node_count: 1 }
            },
            filename: "/tmp/untriggered_fire_and_forget_nodes/untriggered_fire_and_forget_nodes_#{Date.today.to_s}.json",
            hostname: "somehost"
          },
          completed: {
            counts: {
              "fun workflow"=> { workflow_type_count: 1, node_count: 1 }
            }
          },
          time_elapsed: 0,
          range: {
            completed_upper_bound: start_time,
            completed_lower_bound: start_time - 23.hours,
            inconsistent_upper_bound: start_time - 3.hours,
            inconsistent_lower_bound: start_time - 4.hours,
            untriggered_fire_and_forget_upper_bound: start_time - 7.hours
           },
          date: start_time.strftime("%m/%d/%Y")
        })

        subject.perform
      end
    end

    it "sends an email with the report data" do
      Backbeat::Config.options[:alerts] = {
        email_to: "test@backbeat.com",
        email_from: "backbeat@backbeat.com"
      }

      Timecop.freeze(start_time) do
        subject.perform
      end

      email_sent = Mail::TestMailer.deliveries.first
      body = email_sent.to_s

      expect(email_sent.from.first).to eq("backbeat@backbeat.com")
      expect(email_sent.to.first).to eq("test@backbeat.com")
      expect(body).to include("Report finished")
    end

    it "writes inconsistent details to file" do
      Timecop.freeze(start_time) do
        expected_file_contents = {
          inconsistent_node.workflow.id => [inconsistent_node.id]
        }

        allow(subject).to receive(:send_report)
        expect(subject).to receive(:write_inconsistent_nodes_to_file).with(expected_file_contents)

        subject.perform
      end
    end
  end
end

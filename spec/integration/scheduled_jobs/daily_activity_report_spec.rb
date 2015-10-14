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

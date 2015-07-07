require 'spec_helper'
require_relative '../../../reports/daily_activity.rb'

describe Reports::DailyActivity, v2: true do
  context "successful report" do
    let(:start_time) { Time.parse("2015-06-01 00:00:00") }
    let(:user) { FactoryGirl.create(:v2_user) }
    let(:fun_workflow) { FactoryGirl.create(:v2_workflow, user: user, name: "fun workflow") }
    let(:bad_workflow) { FactoryGirl.create(:v2_workflow, user: user, name: "bad workflow") }
    let!(:complete_node) do
      FactoryGirl.create(
        :v2_node,
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
        :v2_node,
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

    it "calls view generation with correct model" do
      Timecop.freeze(start_time) do
        expect_any_instance_of(Reports::DailyActivity).to receive(:send_report).with("report body")
        expect_any_instance_of(Reports::DailyActivity).to receive(:report_html_body) do |report_model|
          expect(report_model.marshal_dump).to eq({
            inconsistent: {
              counts: {
                "bad workflow" => { workflow_type_count: 1, node_count: 1 }
              },
              options: {
                lower_bound: Time.parse("2015-04-01 00:00:00"),
                upper_bound: start_time - 12.hours
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
          "report body"
        end
        Reports::DailyActivity.new.perform
      end
    end

    it "writes inconsistent details to file" do
      Timecop.freeze(start_time) do
        expected_file_contents = {
          inconsistent_node.workflow.id => [inconsistent_node.id]
        }

        subject.stub(:send_report)
        expect(subject).to receive(:write_to_file).with(expected_file_contents)
        subject.perform
      end
    end
  end
end

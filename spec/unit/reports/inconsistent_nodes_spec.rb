require 'spec_helper'
require_relative '../../../reports/inconsistent_nodes.rb'

describe Reports::InconsistentNodes do
  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  context "inconsistent nodes" do
    it "sends an email with file location when it does not fix all nodes" do
      Timecop.freeze do
        finish_time = Time.now + 5.minutes
        incosistent_node = FactoryGirl.create(
          :node,
          name: "bad node",
          parent: workflow,
          fires_at: Time.now - 2.days,
          updated_at: Time.now - 25.hours,
          user: user,
          current_server_status: :ready,
          current_client_status: :ready,
          workflow: workflow
        )

        File.any_instance.should_receive(:write).with({workflow.id.to_s => [incosistent_node.id.to_s]}.to_json) do
          Timecop.freeze(finish_time)
        end

        subject.should_receive(:mail_report).with(
          "Report finished running at: #{finish_time.to_s}\n1 workflows contain inconsistencies.\n"\
          "Total time taken #{5.minutes} seconds\n"\
          "The workflow ids are stored in /tmp/reports_inconsistentnodes/#{Date.today}.txt\n"
        )
        subject.perform
      end
    end
  end

  context "no inconsistent workflows" do
    it "sends an email with file location when it does not fix all nodes" do
      Timecop.freeze do
        finish_time = Time.now + 5.minutes
        incosistent_node = FactoryGirl.create(
          :node,
          name: "bad node",
          parent: workflow,
          fires_at: Time.now - 2.days,
          updated_at: Time.now - 25.hours,
          user: user,
          current_server_status: :complete,
          current_client_status: :complete,
          workflow: workflow
        )

        subject.should_receive(:mail_report).with("No inconsistent workflows to talk about")
        subject.perform
      end
    end
  end


  context "inconsistent_nodes" do
    it "doesn't grab nodes that are deactivated" do
      Timecop.freeze do
        FactoryGirl.create(
          :node,
          name: "bad node",
          parent: workflow,
          fires_at: Time.now - 2.days,
          updated_at: Time.now - 25.hours,
          user: user,
          current_server_status: :deactivated,
          current_client_status: :ready,
          workflow: workflow
        )

        results = Reports::InconsistentNodes.new.inconsistent_nodes({lower_bound: Time.parse('2015/04/01'), upper_bound: 1.day.ago})
        expect(results).to eq([])
      end
    end
  end
end

require 'spec_helper'
require_relative '../../../scheduled_jobs/heal_nodes.rb'

describe ScheduledJobs::HealNodes do
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
          source: "ScheduledJobs::HealNodes",
          message: "Client did not respond within the specified 'complete_by' time",
          node: expired_node.id,
          complete_by: expired_node.node_detail.complete_by
        ).and_call_original

        subject.perform

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
  end
end


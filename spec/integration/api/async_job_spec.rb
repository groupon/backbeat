require 'spec_helper'

describe WorkflowServer::Async::Job do
  it "drops the jobs into Sidekiq" do
    decision = FactoryGirl.create(:decision)
    job = WorkflowServer::Async::Job.schedule(event: decision, method: :send_to_client, args: [1, 2, 3, 4])
    WorkflowServer::Workers::SidekiqJobWorker.should_receive(:perform_async).with(decision.id, :send_to_client, [1,2,3,4], nil)
    job.invoke_job
  end
end

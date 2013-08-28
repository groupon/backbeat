require 'spec_helper'

describe WorkflowServer::Async::Job do
  deploy BACKBEAT_APP

  it "calls the method on the model along with the arguments" do
    decision = FactoryGirl.create(:decision)
    job = WorkflowServer::Async::Job.schedule(event: decision, method: :send_to_client, args: [1, 2, 3, 4])
    WorkflowServer::Models::Decision.any_instance.should_receive(:send_to_client).with(1, 2, 3, 4)
    job.invoke_job
  end
end
require 'spec_helper'

describe WorkflowServer::Async::Job do
  let(:decision) { FactoryGirl.create(:decision) }
  context "#schedule" do
    it "schedules a delayed job" do
      WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      job = Delayed::Job.last
      job.run_at.to_s.should == (Time.now + 2.days).to_s
    end
  end
  context "#perform" do
    before do
      @job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, args: [1,2,3,4], max_attempts: 100}, Time.now + 2.days)
      @dec = mock('decision', some_method: nil, id: 10, name: :make_payment)
      WorkflowServer::Models::Event.stub(find: @dec)
    end
    it "logs start and succeeded messages" do
      @job.payload_object.should_receive(:info).with(id: 10, name: :make_payment, message: "some_method_started")
      @job.payload_object.should_receive(:info).with(id: 10, name: :make_payment, message: "some_method_succeeded")
      @job.invoke_job
    end
    it "calls the method on the given event" do
      WorkflowServer::Models::Event.should_receive(:find).with(decision.id)
      @dec.should_receive(:some_method).with(1, 2, 3, 4)
      @job.invoke_job
    end
  end
end
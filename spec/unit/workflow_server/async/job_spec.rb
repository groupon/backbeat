require 'spec_helper'

describe WorkflowServer::Async::Job do
  let(:decision) { FactoryGirl.create(:decision) }
  context "#schedule" do
    it "schedules a delayed job" do
      WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      Delayed::Job.where(handler: /some_method/).count.should == 1
      job = Delayed::Job.where(handler: /some_method/).first
      job.run_at.to_s.should == (Time.now + 2.days).to_s
      decision.reload._delayed_jobs.should include(job.id)
    end
  end
  context "#perform" do
    before do
      @job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, args: [1,2,3,4], max_attempts: 100}, Time.now + 2.days)
      @dec = mock('decision', some_method: nil, id: 10, name: :make_payment, pull: nil)
      WorkflowServer::Models::Event.stub(find: @dec)
    end
    it "logs start and succeeded messages" do
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", job: anything, id: 10, name: :make_payment, message: "some_method_start_before_hook")
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_started")
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_succeeded")
      @job.invoke_job
    end
    it "calls the method on the given event" do
      WorkflowServer::Models::Event.should_receive(:find).with(decision.id)
      @dec.should_receive(:some_method).with(1, 2, 3, 4)
      @job.invoke_job
    end
    context '#error' do
      it 'records exceptions and raises the error' do
        @dec.should_receive(:some_method).and_raise('some error')
        Squash::Ruby.should_receive(:notify)
        WorkflowServer::Async::Job.should_receive(:error).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_errored", error: anything, backtrace: anything)
        expect {
          @job.invoke_job
        }.to raise_error
      end
    end
  end

  context 'success hook' do
    it "removes the delayed job id from the list of outstanding jobs" do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      decision.reload._delayed_jobs.should include(job.id)
      job.payload_object.success(job)
      decision.reload._delayed_jobs.should_not include(job.id)
    end
  end
end

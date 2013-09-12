require 'spec_helper'

describe WorkflowServer::Async::Job do

  let(:decision) { FactoryGirl.create(:decision) }
  context "#schedule" do
    it "schedules a delayed job" do
      WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      Delayed::Job.where(handler: /some_method/).count.should == 1
      job = Delayed::Job.where(handler: /some_method/).first
      job.run_at.to_s.should == (Time.now.utc + 2.days).to_s
      decision.reload._delayed_jobs.should include(job.id)
    end
  end
  
  context "TorqueBox" do

    it "defines a queue" do
      WorkflowServer::Async::Job.queue.should == '/queues/accounting_backbeat_internal'
    end

    context "Job.perform" do
      it "invokes perform a new instance" do
        args = ["12", :a_method_name, [:arg1, :arg2], 24]
        job  = mock("job")

        WorkflowServer::Async::Job.should_receive(:new)
          .with(*args)
          .and_return(job)

        job.should_receive(:perform)

        processor = WorkflowServer::Async::MessageProcessor.new
        processor.should_receive(:synchronous?).and_return(false)

        message = mock(TorqueBox::Messaging::Message)
        message.stub(:decode).and_return(data: args)
        processor.process!(message)
      end

      it "schedules a delayed job on exception" do
        Timecop.freeze do
          args = ["12", :a_method_name, [:arg1, :arg2], 24]
          event = mock("event")

          WorkflowServer::Async::Job.any_instance.should_receive(:perform)
            .and_raise("Something")

          WorkflowServer::Models::Event.should_receive(:find)
            .with("12")
            .and_return(event)

          WorkflowServer::Async::Job.should_receive(:schedule).with({
            event: event,
            method: :a_method_name,
            args: [:arg1, :arg2],
            max_attempts: 24
          }, Time.now + 5)

          processor = WorkflowServer::Async::MessageProcessor.new

          message = mock(TorqueBox::Messaging::Message)
          message.stub(:decode).and_return(data: args)
          processor.process!(message)
        end
      end
    end

    it "enqueues to TorqueBox" do
      event = mock("event", id: "12")

      job_data = {event: event, method: :a_method_name, args:[:arg1, :arg2], max_attempts: 24}


      TorqueBox::Messaging::Queue.any_instance.should_receive(:publish)
        .with(data: ["12", :a_method_name, [:arg1, :arg2], 24])

      WorkflowServer::Async::Job.enqueue(job_data)
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
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_succeeded", duration: 0.0)
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
        WorkflowServer::Async::Job.should_receive(:error).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_errored", error: anything, backtrace: anything, duration: 0.0)
        expect {
          @job.invoke_job
        }.to raise_error
      end
    end
  end

  context 'success hook' do
    it 'removes the delayed job id from the list of outstanding jobs' do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      decision.reload._delayed_jobs.should include(job.id)
      job.payload_object.success(job)
      decision.reload._delayed_jobs.should_not include(job.id)
    end
  end

  context 'failure hook' do
    it 'updates the events status to async_job_error when method to call is NOT "notify_client"' do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      job.payload_object.failure
      decision.reload.status.should == :error
      decision.status_history.last['error'].should == :async_job_error
    end
    it 'does NOT update the events status to async_job_error when method to call is "notify_client"' do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :notify_client, max_attempts: 100}, Time.now + 2.days)
      job.payload_object.failure
      decision.reload.status.should_not == :error
    end
    it 'rescues from and does not reaise any Exception' do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      decision.destroy
      expect{job.payload_object.failure}.to_not raise_error
    end
    it 'rescues any Exception and logs it' do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      decision.destroy
      WorkflowServer::Async::Job.should_receive(:error).with(source: WorkflowServer::Async::Job.to_s, message: 'encountered error in AsyncJob failure hook', error: anything, backtrace: anything)
      job.payload_object.failure
    end
  end
end

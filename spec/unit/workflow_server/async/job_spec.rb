require 'spec_helper'

describe WorkflowServer::Async::Job do

  let(:decision) { FactoryGirl.create(:decision) }
  context '#schedule' do
    it 'schedules a delayed job' do
      WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 20.minutes)
      Delayed::Job.where(handler: /some_method/).count.should == 1
      job = Delayed::Job.where(handler: /some_method/).first
      job.run_at.to_s.should == (Time.now.utc + 20.minutes).to_s
      decision.reload._delayed_jobs.should include(job.id)
    end
  end

  context 'Job.perform' do
    it 'invokes perform on a new instance' do
      args = ['12', :a_method_name, [:arg1, :arg2], 24]
      job  = double('job')

      WorkflowServer::Async::Job.should_receive(:new).with(*args).and_return(job)

      job.should_receive(:perform)

      WorkflowServer::Async::Job.perform('data' => args)
    end

    it 'schedules a delayed job on exception' do
      Timecop.freeze do
        args = ['12', :a_method_name, [:arg1, :arg2], 24]
        event = double('event')

        WorkflowServer::Async::Job.any_instance.should_receive(:perform).and_raise('Something')

        WorkflowServer::Async::Job.should_receive(:schedule).with({ event_id: '12',
                                                                    method: :a_method_name,
                                                                    args: [:arg1, :arg2],
                                                                    max_attempts: 24},
                                                                    Time.now + 10)

        WorkflowServer::Async::Job.perform('data' => args)
      end
    end

    it 'enqueues to Sidekiq' do
      event = double('event', id: '12')
      job_data = {event: event, method: :a_method_name, args:[:arg1, :arg2], max_attempts: 24}

      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:perform_async).with(data: ['12', :a_method_name, [:arg1, :arg2], 24])

      WorkflowServer::Async::Job.enqueue(job_data)
    end
  end

  context '#perform' do
    before do
      @dec = double('decision', some_method: nil, id: 10, name: :make_payment, pull: nil, push: nil)
      @job = WorkflowServer::Async::Job.schedule({event: @dec, method: :some_method, args: [1,2,3,4], max_attempts: 100}, Time.now + 2.days)
      WorkflowServer::Models::Event.stub(find: @dec)
    end

    it 'logs start and succeeded messages' do
      WorkflowServer::Async::Job.should_receive(:info).with(source: 'WorkflowServer::Async::Job', job: anything, id: 10, name: :make_payment, message: 'some_method_start_before_hook').ordered
      WorkflowServer::Async::Job.should_receive(:info).with(source: 'WorkflowServer::Async::Job', id: 10, name: :make_payment, message: 'some_method_started').ordered
      WorkflowServer::Async::Job.should_receive(:info).with(source: 'WorkflowServer::Async::Job', id: 10, name: :make_payment, message: 'some_method_succeeded', duration: 0.0).ordered
      @job.invoke_job
    end

    it 'calls the method on the given event' do
      WorkflowServer::Models::Event.should_receive(:find).with(@dec.id)
      @dec.should_receive(:some_method).with(1, 2, 3, 4)
      @job.invoke_job
    end

    context '#error' do
      it 'records exceptions and raises the error if they are NOT Backbeat::TransientError' do
        @dec.should_receive(:some_method).and_raise('some error')
        Squash::Ruby.should_receive(:notify)
        WorkflowServer::Async::Job.should_receive(:error).with(source: 'WorkflowServer::Async::Job', id: 10, name: :make_payment, message: 'some_method_errored', error: anything, backtrace: anything, duration: 0.0)
        expect {
          @job.invoke_job
        }.to raise_error
      end
    end
    it 'records exceptions as INFO and reraises if they are Backbeat::TransientError' do
      # We have to expect these first two so that we can accurately test the third, but we don't really care about these in this test
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", job: anything, id: 10, name: :make_payment, message: "some_method_start_before_hook").ordered
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_started").ordered

      @dec.should_receive(:some_method).and_raise(Backbeat::TransientError.new(Exception.new('test')))
      WorkflowServer::Async::Job.should_receive(:info).with(source: "WorkflowServer::Async::Job", id: 10, name: :make_payment, message: "some_method_transient_error", error: anything, backtrace: anything, duration: 0.0).ordered
      expect {
        @job.invoke_job
      }.to raise_error(Backbeat::TransientError)
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
    it "updates the events status to async_job_error when method to call is NOT 'notify_client'" do
      job = WorkflowServer::Async::Job.schedule({event: decision, method: :some_method, max_attempts: 100}, Time.now + 2.days)
      job.payload_object.failure
      decision.reload.status.should == :error
      decision.status_history.last['error'].should == :async_job_error
    end
    it "does NOT update the events status to async_job_error when method to call is 'notify_client'" do
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

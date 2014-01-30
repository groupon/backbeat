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

  context '#enqueue' do
    it 'enqueues to Sidekiq' do
      event = double('event', id: '12')
      job_data = {event: event, method: :a_method_name, args:[:arg1, :arg2], max_attempts: 24}

      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:perform_async).with('12', :a_method_name, [:arg1, :arg2], 24)

      WorkflowServer::Async::Job.enqueue(job_data)
    end

    it 'enqueues to Sidekiq immediately if run_at is before now' do
      event = double('event', id: '12')
      job_data = {event: event, method: :a_method_name, args:[:arg1, :arg2], max_attempts: 24}

      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:perform_async).with('12', :a_method_name, [:arg1, :arg2], 24)

      WorkflowServer::Async::Job.enqueue(job_data, Time.now - 30)
    end

    it 'enqueues to Sidekiq with a delay if run_at is after now' do
      event = double('event', id: '12')
      job_data = {event: event, method: :a_method_name, args:[:arg1, :arg2], max_attempts: 24}

      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:perform_in).with(30, '12', :a_method_name, [:arg1, :arg2], 24)

      WorkflowServer::Async::Job.enqueue(job_data, Time.now + 30)
    end
  end

  context '#perform' do
    before do
      @dec = double('decision', some_method: nil, id: 10, name: :make_payment, pull: nil, push: nil)
      @job = WorkflowServer::Async::Job.schedule({event: @dec, method: :some_method, args: [1,2,3,4], max_attempts: 100}, Time.now + 2.days)
      WorkflowServer::Models::Event.stub(find: @dec)
    end

    it 'drops the job into sidekiq' do
      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:perform_async).with(@dec.id, :some_method, [1,2,3,4], 100)
      @job.invoke_job
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

require 'spec_helper'

describe WorkflowServer::Workers::SidekiqJobWorker do

  subject { WorkflowServer::Workers::SidekiqJobWorker }

  let(:decision) { decision = FactoryGirl.create(:decision) }
  let(:job_data) { [decision.id, :status, [:arg1, :arg2], 5] }

  it { should be_retryable 12 }
  it { should be_processed_in :accounting_backbeat_server }


  context 'retries exhuasted' do
    it 'marks the event in question as errored and logs that it failed' do
      subject.should_receive(:error).with("#{subject} failed with #{job_data}: BadError.")

      subject.sidekiq_retries_exhausted_block.call({'class' => subject, 'args' => job_data, 'error_message' => 'BadError'})

      decision.reload.status.should == :error
    end

    it 'logs that it could not mark the event as errored if it gets and exception while updating the event' do
      WorkflowServer::Models::Decision.any_instance.stub(:errored).and_raise('WorstError')

      subject.should_receive(:error).with("#{subject} failed with #{job_data}: BadError and could not mark the Event(#{decision.id}) as errored because of RuntimeError:WorstError.")

      subject.sidekiq_retries_exhausted_block.call({'class' => subject, 'args' => job_data, 'error_message' => 'BadError'})
    end
  end

  context '#perform' do
    it 'should call the method on the event with the given args' do
      WorkflowServer::Models::Decision.any_instance.should_receive(:status).with(:arg1, :arg2)
      subject.new.perform(*job_data)
    end

    it 'logs start and succeeded messages' do
      WorkflowServer::Models::Decision.any_instance.stub(:status) # stub so we don't get wrong number of arguements error
      subject.should_receive(:info).with(source: subject.to_s, id: decision.id, name: decision.name, message: 'status_started').ordered
      subject.should_receive(:info).with(source: subject.to_s, id: decision.id, name: decision.name, message: 'status_succeeded', duration: 0.0).ordered
      subject.new.perform(*job_data)
    end

    context 'error' do
      it 'records exceptions and reraises the error if they are NOT Backbeat::TransientError' do
        WorkflowServer::Models::Decision.any_instance.should_receive(:status).and_raise('some error')
        subject.should_receive(:error).with(source: subject.to_s, id: decision.id, name: decision.name, message: 'status_errored', error: anything, backtrace: anything, duration: 0.0)
        Squash::Ruby.should_receive(:notify)
        expect {
          subject.new.perform(*job_data)
        }.to raise_error
      end

      it 'records exceptions as INFO and reraises if they are Backbeat::TransientError' do
        # We have to expect these first two so that we can accurately test the third, but we don't really care about these in this test
        subject.should_receive(:info).with(source: subject.to_s, id: decision.id, name: decision.name, message: "status_started").ordered

        WorkflowServer::Models::Decision.any_instance.should_receive(:status).and_raise(Backbeat::TransientError.new(Exception.new('test')))
        subject.should_receive(:info).with(source: subject.to_s, id: decision.id, name: decision.name, message: "status:test", error: anything, backtrace: anything, duration: 0.0).ordered
        expect {
          subject.new.perform(*job_data)
        }.to raise_error(Backbeat::TransientError)
      end

      it 'records exceptions as INFO and reraises if they are EventNotFound' do
        WorkflowServer::Models::Event.should_receive(:find).and_return(nil) # this is the real exception
        subject.should_receive(:info).with(source: subject.to_s, id: decision.id, name: 'unknown', message: "status:Event with id(#{decision.id}) not found", error: anything, backtrace: anything, duration: 0.0).ordered
        expect {
          subject.new.perform(*job_data)
        }.to raise_error(WorkflowServer::EventNotFound)
      end
    end
  end

end

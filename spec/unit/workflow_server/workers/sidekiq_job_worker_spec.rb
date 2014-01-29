require 'spec_helper'

describe WorkflowServer::Workers::SidekiqJobWorker do

  let(:decision) { decision = FactoryGirl.create(:decision) }
  let(:job_data) { [decision.id, :status, [:arg1, :arg2], 5] }

  it { should be_retryable 12 }
  it { should be_processed_in :accounting_backbeat_server }

  context '#perform' do
    it 'should call the method on the event with the given args' do
      WorkflowServer::Models::Decision.any_instance.should_receive(:status).with(:arg1, :arg2)
      WorkflowServer::Workers::SidekiqJobWorker.new.perform(*job_data)
    end

    it 'logs start and succeeded messages' do
      WorkflowServer::Models::Decision.any_instance.stub(:status) # stub so we don't get wrong number of arguements error
      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:info).with(source: 'WorkflowServer::Workers::SidekiqJobWorker', id: decision.id, name: decision.name, message: 'status_started').ordered
      WorkflowServer::Workers::SidekiqJobWorker.should_receive(:info).with(source: 'WorkflowServer::Workers::SidekiqJobWorker', id: decision.id, name: decision.name, message: 'status_succeeded', duration: 0.0).ordered
      WorkflowServer::Workers::SidekiqJobWorker.new.perform(*job_data)
    end

    context 'error' do
      it 'records exceptions and reraises the error if they are NOT Backbeat::TransientError' do
        WorkflowServer::Models::Decision.any_instance.should_receive(:status).and_raise('some error')
        WorkflowServer::Workers::SidekiqJobWorker.should_receive(:error).with(source: 'WorkflowServer::Workers::SidekiqJobWorker', id: decision.id, name: decision.name, message: 'status_errored', error: anything, backtrace: anything, duration: 0.0)
        Squash::Ruby.should_receive(:notify)
        expect {
          WorkflowServer::Workers::SidekiqJobWorker.new.perform(*job_data)
        }.to raise_error
      end

      it 'records exceptions as INFO and reraises if they are Backbeat::TransientError' do
        # We have to expect these first two so that we can accurately test the third, but we don't really care about these in this test
        WorkflowServer::Workers::SidekiqJobWorker.should_receive(:info).with(source: "WorkflowServer::Workers::SidekiqJobWorker", id: decision.id, name: decision.name, message: "status_started").ordered

        WorkflowServer::Models::Decision.any_instance.should_receive(:status).and_raise(Backbeat::TransientError.new(Exception.new('test')))
        WorkflowServer::Workers::SidekiqJobWorker.should_receive(:info).with(source: "WorkflowServer::Workers::SidekiqJobWorker", id: decision.id, name: decision.name, message: "status:test", error: anything, backtrace: anything, duration: 0.0).ordered
        expect {
          WorkflowServer::Workers::SidekiqJobWorker.new.perform(*job_data)
        }.to raise_error(Backbeat::TransientError)
      end

      it 'records exceptions as INFO and reraises if they are EventNotFound' do
        WorkflowServer::Models::Event.should_receive(:find).and_return(nil) # this is the real exception
        WorkflowServer::Workers::SidekiqJobWorker.should_receive(:info).with(source: "WorkflowServer::Workers::SidekiqJobWorker", id: decision.id, name: 'unknown', message: "status:Event with id(#{decision.id}) not found", error: anything, backtrace: anything, duration: 0.0).ordered
        expect {
          WorkflowServer::Workers::SidekiqJobWorker.new.perform(*job_data)
        }.to raise_error(WorkflowServer::EventNotFound)
      end
    end
  end

end

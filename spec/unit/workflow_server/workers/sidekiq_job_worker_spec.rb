require 'spec_helper'

describe WorkflowServer::Workers::SidekiqJobWorker do

  let(:job_data) { {event: 'SomeEvent', method: :testing_method_missing, args: [:arg1, :arg2], max_attempts: 5 } }

  it { should be_retryable 12 }
  it { should be_processed_in :accounting_backbeat_server }

  context '#perform' do
    it 'should call WorkflowServer::Async::Job.perform with the job_data it is called with' do
      WorkflowServer::Async::Job.should_receive(:perform).with(job_data)
      WorkflowServer::Workers::SidekiqJobWorker.new.perform(job_data)
    end
  end

end

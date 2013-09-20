require 'sidekiq'
require 'workflow_server/config'

module WorkflowServer
  module Workers
    class SidekiqJobWorker
      include Sidekiq::Worker
      sidekiq_options retry: 12,
                      backtrace:  true,
                      queue: WorkflowServer::Config.options[:async_queue]

      def perform(job_data)
        # we just pass this straight through to the Async::Job perform
        WorkflowServer::Async::Job.perform(job_data)
      end

    end
  end
end

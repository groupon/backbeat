require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module V2
  module Workers
    class AsyncWorker
      include Sidekiq::Worker

      sidekiq_options retry: false,
        backtrace: true,
        queue: WorkflowServer::Config.options[:async_queue_v2]

      def self.schedule_async_event(node, method, time, retries_remaining = 4)
        perform_at(time, node.class.name, node.id, method, retries_remaining)
      end

      def self.async_event(node, method, retries_remaining = 4)
        perform_async(node.class.name, node.id, method, retries_remaining)
      end

      def perform(node_class, node_id, method, retries_remaining = 0)
        node = node_class.constantize.find(node_id)
        V2::Processors.perform(method.to_sym, node, server_retries_remaining: retries_remaining)
      end
    end
  end
end

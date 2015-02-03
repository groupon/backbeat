require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module V2
  module Workers
    class AsyncWorker
      include Sidekiq::Worker

      sidekiq_options retry: 4,
        backtrace: true,
        queue: WorkflowServer::Config.options[:async_queue_v2]

      sidekiq_retries_exhausted do |msg|
        args = msg['args']
        node = args[0].constantize.find(args[1])
        Server.fire_event(Server::ClientError, node, { error_message: msg["error_message"] })
      end

      def self.schedule_async_event(node, method, time)
        perform_at(time, node.class.name, node.id, method)
      end

      def self.async_event(node, method)
        perform_async(node.class.name, node.id, method)
      end

      def perform(node_class, node_id, method)
        node = node_class.constantize.find(node_id)
        Instrument.instrument(node, method) do
          Processors.send(method, node)
        end
      end
    end
  end
end

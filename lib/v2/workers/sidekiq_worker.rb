require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module V2
  module Workers
    class SidekiqWorker
      include Sidekiq::Worker

      sidekiq_options retry: 12,
                      backtrace: true,
                      queue: WorkflowServer::Config.options[:async_queue_v2]

      sidekiq_retries_exhausted do |msg|
        args = msg['args']
        node = args[0].constantize.find(args[1])
        V2::Server.fire_event(V2::Server::ClientError, node)
      end

      def self.async_event(node, method)
        V2::Workers::SidekiqWorker.perform_async(node.class.name, node.id, method)
      end

      def perform(node_class, node_id, method)
        node = node_class.constantize.find(node_id)
        instrument(node, method) do
           V2::Processors.send(method, node)
        end
      end

      private

      def instrument(node, method)
        t0 = Time.now
        log_msg(node, "#{method}_started")
        result = yield
        log_msg(node, "#{method}_succeeded", duration: Time.now - t0)
        return result
      rescue Exception => error
        log_msg(node, "#{method}_errored",
          error_class: error.class,
          error: error.to_s,
          backtrace: error.backtrace,
          duration: Time.now - t0
        )
        raise error
      end

      def log_msg(node, message, options = {})
        Logger.info({
          source: self.class.to_s,
          id: node.id,
          name: node.name,
          message: message
        }.merge(options))
      end
    end
  end
end

require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/logger'
require 'workflow_server/errors'
require 'workflow_server/config'

module V2
  module Workers
    class SidekiqWorker
      include Sidekiq::Worker
      extend WorkflowServer::Logger

      sidekiq_options retry: 12,
                      backtrace:  true,
                      queue: WorkflowServer::Config.options[:async_queue_v2]

      def self.async_event(node, method)
        V2::Workers::SidekiqWorker.perform_async(node.class.name, node.id, method)
      end

      def perform(node_class, node_id, method)
        node = node_class.constantize.find(node_id)
        instrument(node, method) do
           V2::Processors.send(method, node)
        end
      end

      def instrument(node, method)
        t0 = Time.now
        self.class.info(source: self.class.to_s, id: node.id, name: node.name, message: "#{method}_started")
        result = yield
        self.class.info(source: self.class.to_s, id: node.id, name: node.name, message: "#{method}_succeeded", duration: Time.now - t0)
        return result
        rescue Exception => error
        self.class.info(source: self.class.to_s, id: node.id, name: node.name, message: "#{method}_errored", error_class: error.class, error: error.to_s, backtrace: error.backtrace, duration: Time.now - t0)
        raise error
      end
    end
  end
end

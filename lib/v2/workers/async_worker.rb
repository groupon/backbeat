require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module V2
  module Workers
    class AsyncWorker
      include Sidekiq::Worker
      include WorkflowServer::Logger

      sidekiq_options retry: false, queue: WorkflowServer::Config.options[:async_queue_v2]

      def self.schedule_async_event(event, node, options)
        info(status: :schedule_async_event_started, node: node.id, event: event.name)
        node_data = { node_class: node.class.name, node_id: node.id }
        time = options.fetch(:time, Time.now)
        perform_at(time, event.name, node_data, options)
        info(status: :schedule_async_event_finished, node: node.id, event: event.name)
      end

      def perform(event_class, node_data, options)
        info(status: :perform_started, node_data: node_data, event: event_class, options: options)
        options = options.reduce({}) { |m, (k, v)| m[k.to_sym] = v; m }
        node = deserialize_node(event_class, node_data, options)
        if node
          Server.fire_event(event_class.constantize, node, Async::PerformEvent.new(options))
          info(status: :perform_finished, node: node.id, event: event_class)
        end
      end

      private

      def deserialize_node(event_class, node_data, options)
        node_class = node_data["node_class"]
        node_id = node_data["node_id"]
        node_class.constantize.find(node_id)
      rescue => e
        info(status: :deserialize_node_error, error: e, backtrace: e.backtrace)
        AsyncWorker.perform_at(Time.now + 10.minutes, event_class, node_data, options)
        false
      end
    end
  end
end

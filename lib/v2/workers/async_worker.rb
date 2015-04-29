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
        Server.fire_event(event_class.constantize, node, Async::PerformEvent)
        info(status: :perform_finished, node: node.id, event: event_class)
      rescue => e
        retries = options.fetch(:retries, 4)
        if retries > 0
          AsyncWorker.perform_at(Time.now + 30.seconds, event_class, node_data, options.merge(retries: retries - 1))
        else
          if node
            StateManager.call(node, current_server_status: :errored)
            Client.notify_of(node, "error", e)
          else
            info(status: :deserialize_node_error, error: e, backtrace: e.backtrace)
          end
        end
        raise e
      end

      private

      def deserialize_node(event_class, node_data, options)
        node_class = node_data["node_class"]
        node_id = node_data["node_id"]
        node_class.constantize.find(node_id)
      end
    end
  end
end

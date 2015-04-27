require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module V2
  module Workers
    class AsyncWorker
      include Sidekiq::Worker
      include WorkflowServer::Logger

      sidekiq_options retry: false, backtrace: true, queue: WorkflowServer::Config.options[:async_queue_v2]

      def self.schedule_async_event(event, node, time, retries_remaining)
        info(status: :schedule_async_event_started, node: node.id, event: event.name)
        node_data = { node_class: node.class.name, node_id: node.id }
        perform_at(time, event.name, node_data, retries_remaining)
        info(status: :schedule_async_event_finished, node: node.id, event: event.name)
      end

      def perform(event_class, node_data, retries_remaining)
        if node = deserialize_node(node_data)
          info(status: :perform_started, node: node.id, event: event_class)
          Server.fire_event(event_class.constantize, node, Schedulers::PerformEvent.new(retries_remaining))
          info(status: :perform_finished, node: node.id, event: event_class)
        else
          AsyncWorker.perform_at(Time.now + 10.seconds, event_class, node_data, retries_remaining)
        end
      end

      private

      def deserialize_node(node_data)
        node_class = node_data["node_class"]
        node_id = node_data["node_id"]
        node_class.constantize.find(node_id)
      rescue => e
        info(status: :deserialize_node_error, error: e, node_data: node_data)
        false
      end
    end
  end
end

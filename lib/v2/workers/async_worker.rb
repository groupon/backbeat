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
        business_perform(event_class, node_data, options)
        info(status: :perform_finished, node: node_data, event: event_class)
      end

      private

      def business_perform(event_class, node_data, options)
        options = symbolize_keys(options)
        node = deserialize_node(node_data)
        Server.fire_event(event_class.constantize, node, Schedulers::PerformEvent)
      rescue DeserializeError => e
        error(status: :deserialize_node_error, node: node_data["node_id"], error: e, backtrace: e.backtrace)
        raise e
      rescue => e
        handle_processing_error(e, event_class, node, options)
      end

      def handle_processing_error(e, event_class, node, options)
        retries = options.fetch(:retries, 4)
        if retries > 0
          new_options = options.merge(retries: retries - 1, time: Time.now + 30.seconds)
          AsyncWorker.schedule_async_event(event_class.constantize, node, new_options)
        else
          info(status: :retries_exhausted, event_class: event_class, node: node.id, options: options, error: e, backtrace: e.backtrace)
          Server.fire_event(Events::ServerError, node)
        end
      rescue => e
        error(status: :uncaught_exception, event_class: event_class, node: node.id, options: options, error: e, backtrace: e.backtrace)
        raise e
      end

      def symbolize_keys(options)
        options.reduce({}) { |m, (k, v)| m[k.to_sym] = v; m }
      end

      def deserialize_node(node_data)
        node_class = node_data["node_class"]
        node_id = node_data["node_id"]
        node_class.constantize.find(node_id)
      rescue => e
        raise DeserializeError.new(e.message)
      end
    end
  end
end

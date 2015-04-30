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
        process_event(event_class, node_data, options)
      rescue NodeServerError=> e
        handle_processing_error(e, event_class, node_data, options) do |e|
          Server.fire_event(Events::ServerError, e.node)
        end
      rescue => e
        handle_processing_error(e, event_class, node_data, options) do |e|
          info(status: :deserialize_node_error, error: e, backtrace: e.backtrace)
        end
      end

      def handle_processing_error(e, event_class, node_data, options)
        retries = options.fetch(:retries, 4)
        if retries > 0
          new_options = options.merge(retries: retries - 1)
          AsyncWorker.perform_at(Time.now + 30.seconds, event_class, node_data, new_options)
        else
          yield e
        end
        raise e
      end

      def process_event(event_class, node_data, options)
        node = deserialize_node(node_data)
        fire(event_class, node)
      end

      class NodeServerError < StandardError
        attr_reader :node

        def initialize(node, e)
          @node = node
          super(e.message)
        end
      end

      def fire(event_class, node)
        Server.fire_event(event_class.constantize, node, Async::PerformEvent)
      rescue => e
        raise NodeServerError.new(node, e)
      end

      def symbolize_keys(options)
        options.reduce({}) { |m, (k, v)| m[k.to_sym] = v; m }
      end

      def deserialize_node(node_data)
        node_class = node_data["node_class"]
        node_id = node_data["node_id"]
        node_class.constantize.find(node_id)
      end
    end
  end
end

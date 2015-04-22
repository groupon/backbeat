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
        info(source: "V2::AsyncWorker", status: :schedule_async_event_started, node: node.id, event: event.name)
        perform_at(time, event.name, node.class.name, node.id, retries_remaining)
        info(source: "V2::AsyncWorker", status: :schedule_async_event_finished, node: node.id, event: event.name)
      end

      def perform(event_class, node_class, node_id, retries_remaining)
        info(source: "V2::AsyncWorker", status: :perform_started, node: node_id, event: event_class)
        event = event_class.constantize
        node = node_class.constantize.find(node_id)
        Server.fire_event(event, node, Schedulers::PerformEvent.new(retries_remaining))
        info(source: "V2::AsyncWorker", status: :perform_finished, node: node_id, event: event_class)
      end
    end
  end
end

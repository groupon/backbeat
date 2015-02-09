require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module V2
  module Workers
    class AsyncWorker
      include Sidekiq::Worker

      sidekiq_options retry: false, backtrace: true, queue: WorkflowServer::Config.options[:async_queue_v2]

      def self.schedule_async_event(event, node, time, retries_remaining = 4)
        perform_at(time, event.name, node.class.name, node.id, retries_remaining)
      end

      def perform(event_class, node_class, node_id, retries_remaining)
        event = event_class.constantize
        node = node_class.constantize.find(node_id)
        Server.fire_event(event, node, Schedulers::NowScheduler.new(retries_remaining))
      end
    end
  end
end

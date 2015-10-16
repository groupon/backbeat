require 'sidekiq'
require 'sidekiq/schedulable'

module Backbeat
  module Workers
    class HealNodes
      include Logging
      include Sidekiq::Worker
      include Sidekiq::Schedulable

      sidekiq_options retry: false, queue: Config.options[:async_queue]
      sidekiq_schedule Config.options[:schedules][:heal_nodes], last_run: true

      CLIENT_TIMEOUT_ERROR = "Client did not respond within the specified 'complete_by' time"
      UNEXPECTED_STATE_MESSAGE = "Node with expired 'complete_by' is not in expected state"

      def perform(last_run)
        last_run_time = Time.at(last_run)
        expired_node_details(last_run_time).each do |node_detail|
          node = node_detail.node

          if received_by_client?(node)
            info(message: CLIENT_TIMEOUT_ERROR, node: node.id, complete_by: node_detail.complete_by)
            Server.fire_event(Events::ClientError.new(CLIENT_TIMEOUT_ERROR), node)
          else
            info(message: UNEXPECTED_STATE_MESSAGE, node: node.id, complete_by: node_detail.complete_by)
          end
        end
      end

      private

      def expired_node_details(last_run_time)
        NodeDetail.where(complete_by: last_run_time..Time.now).select(:node_id, :complete_by)
      end

      def received_by_client?(node)
        node.current_server_status == "sent_to_client" && node.current_client_status == "received"
      end
    end
  end
end

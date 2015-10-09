require 'sidekiq'
require 'sidekiq/schedulable'

module Backbeat
  module Workers
    class HealNodes
      include Logging
      include Sidekiq::Worker
      include Sidekiq::Schedulable

      sidekiq_options retry: false, queue: Config.options[:async_queue]
      sidekiq_schedule '0 */2 * * * *'

      CLIENT_TIMEOUT_ERROR = "Client did not respond within the specified 'complete_by' time"
      UNEXPECTED_STATE_MESSAGE = "Node with expired 'complete_by' is not in expected state"
      SEARCH_PADDING = 3600 # used in case the search does not run on time

      def perform
        expired_node_details.each do |node_detail|
          node = node_detail.node

          if received_by_client?(node)
            info(source: self.class.to_s, message: CLIENT_TIMEOUT_ERROR, node: node.id, complete_by: node_detail.complete_by)
            Backbeat::Server.fire_event(Backbeat::Events::ClientError.new(CLIENT_TIMEOUT_ERROR), node)
          else
            info(source: self.class.to_s, message: UNEXPECTED_STATE_MESSAGE, node: node.id, complete_by: node_detail.complete_by)
          end
        end
      end

      private

      def expired_node_details
        frequency = Backbeat::Config.options[:job_frequency][:heal_nodes]
        search_lower_bound = Time.now - frequency - SEARCH_PADDING
        Backbeat::NodeDetail.where(complete_by: search_lower_bound..Time.now).select("node_id, complete_by")
      end

      def received_by_client?(node)
        node.current_server_status == "sent_to_client" && node.current_client_status == "received"
      end
    end
  end
end

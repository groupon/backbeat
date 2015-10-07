require_relative 'base'

module ScheduledJobs
  class HealNodes < Base
    CLIENT_TIMEOUT_ERROR = "Client did not respond within the specified 'complete_by' time"

    def perform
      resend_expired_nodes
    end

    private

    def resend_expired_nodes
      expired_node_details.each do |node_detail|
        node = node_detail.node

        if received_by_client?(node)
          info(source: self.class.to_s, message: CLIENT_TIMEOUT_ERROR, node: node.id, complete_by: node_detail.complete_by)
          Backbeat::Server.fire_event(Backbeat::Events::ClientError.new(CLIENT_TIMEOUT_ERROR), node)
        end
      end
    end

    def expired_node_details
      search_lower_bound = Backbeat::Config.options[:client_timeout][:search_frequency]
      Backbeat::NodeDetail.where(complete_by: (Time.now - search_lower_bound)..Time.now).select("node_id, complete_by")
    end

    def received_by_client?(node)
      node.current_server_status == "sent_to_client" && node.current_client_status == "received"
    end
  end
end

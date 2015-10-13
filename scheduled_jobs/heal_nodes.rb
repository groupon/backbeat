require_relative 'base'

module ScheduledJobs
  class HealNodes < Base
    CLIENT_TIMEOUT_ERROR = "Client did not respond within the specified 'complete_by' time"
    SEARCH_PADDING = 1.hour # used in case the search does not run on time

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
      search_lower_bound = Time.now - Backbeat::Config.options[:job_frequency][:heal_nodes] - SEARCH_PADDING
      Backbeat::NodeDetail.where(complete_by: (search_lower_bound..Time.now)).select("node_id, complete_by")
    end

    def received_by_client?(node)
      node.current_server_status == "sent_to_client" && node.current_client_status == "received"
    end
  end
end

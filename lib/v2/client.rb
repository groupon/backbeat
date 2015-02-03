require "workflow_server/client"
require "workflow_server/errors"

module V2
  module Client
    def self.notify_of(node, message, error = nil)
      notification_hash = {
        notification: {
          type: node.class.to_s,
          id: node.id,
          name: node.name,
          subject: node.subject,
          message: message
        },
        error: error
      }
      response = WorkflowServer::Client.post(node.user.notification_endpoint, notification_hash)
      raise WorkflowServer::HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
    end

    DECISION_WHITE_LIST = [:decider, :subject, :id, :name, :parent_id, :user_id]
    ACTIVITY_WHITE_LIST = [:id, :mode, :name, :name, :parent_id, :workflow_id, :user_id, :client_data]

    def self.perform_action(node)
      if node.legacy_type == 'signal'
        decision = node.attributes.merge(
          subject: node.subject,
          decider: node.decider
        )
        WorkflowServer::Client.make_decision(
          decision.keep_if { |k, _| DECISION_WHITE_LIST.include? k.to_sym },
          node.user
        )
      else
        activity = node.attributes.merge(client_data: node.client_node_detail.data)
        WorkflowServer::Client.perform_activity(
          activity.keep_if { |k, _| ACTIVITY_WHITE_LIST.include? k.to_sym },
          node.user
        )
      end
    end
  end
end

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
        }
      }
      notification_hash.merge!(error: error_hash(error)) if error

      response = WorkflowServer::Client.post(node.user.notification_endpoint, notification_hash)
      raise WorkflowServer::HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
    end

    DECISION_WHITE_LIST = [:decider, :subject, :id, :name, :parent_id, :user_id]
    ACTIVITY_WHITE_LIST = [:id, :mode, :name, :name, :parent_id, :workflow_id, :user_id, :client_data]

    def self.perform_action(node)
      if node.legacy_type == 'signal' || node.legacy_type == 'timer'
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

    def self.error_hash(error)
      case error
      when StandardError
        error_hash = {error_klass: error.class.to_s, message: error.message}
        if error.backtrace
          error_hash[:backtrace] = error.backtrace
        end
        error_hash
      when String
        {error_klass: error.class.to_s, message: error}
      else
        error
      end
    end
  end
end

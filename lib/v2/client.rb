require "workflow_server/client"
require "workflow_server/errors"
require "v2/client/serializers"

module V2
  module Client
    def self.notify_of(node, message, error = nil)
      notification = Client::NotificationSerializer.call(node, message, error)
      response = WorkflowServer::Client.post(node.user.notification_endpoint, notification)
      raise WorkflowServer::HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
    end

    def self.perform_action(node)
      if node.decision?
        WorkflowServer::Client.make_decision(Client::DecisionSerializer.call(node), node.user)
      else
        WorkflowServer::Client.perform_activity(Client::ActivitySerializer.call(node), node.user)
      end
    end
  end
end

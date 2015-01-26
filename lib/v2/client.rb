require "workflow_server/client"
require "workflow_server/errors"

module V2
  module Client
    def self.notify_of(node, message, error = nil)
      workflow = node.is_a?(V2::Workflow) ? node : node.workflow
      notification_hash = {
        notification: {
          type: node.class.to_s,
          id: node.id,
          name: node.name,
          subject: workflow.subject,
          message: message,
          error: error
        }
      }
      response = WorkflowServer::Client.post(node.user.notification_endpoint, notification_hash)
      raise WorkflowServer::HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
    end
  end
end

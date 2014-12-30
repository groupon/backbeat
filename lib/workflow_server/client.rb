require 'httparty'
require_relative 'helper'

module WorkflowServer
  module Client

    def self.perform_activity(activity, user = nil)
      ap "here"
      user ||= activity.my_user
      if (url = user.try(:activity_endpoint))
        response = post(url, activity: activity.serializable_hash)
        raise WorkflowServer::HttpError.new("http request to perform_activity failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.make_decision(decision, user = nil)
      user ||= decision.my_user
      if (url = user.try(:decision_endpoint))
        response = post(url, decision: decision.is_a?(Hash) ?  decision : decision.serializable_hash)
        raise WorkflowServer::HttpError.new("http request to make_decision failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.notify_of(event, notification, error = nil)
      workflow = event.is_a?(WorkflowServer::Models::Workflow) ? event : event.workflow
      notification_hash = { notification: { type: event.event_type, event: event.id, name: event.name, subject: workflow.try(:subject), message: notification } }

      if (url = event.my_user.try(:notification_endpoint))
        notification_hash.merge!(error: error) if error
        response = post(url, notification_hash)
        raise WorkflowServer::HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.post(url, params = {})
      params = params.dup
      body = WorkflowServer::Helper::HashKeyTransformations.camelize_keys(params).to_json
      ::HTTParty.post(url, body: body, headers: {"Content-Type" => "application/json", "Content-Length" => body.size.to_s})
    end
  end
end

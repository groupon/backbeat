require 'httparty'
require_relative 'helper'

module WorkflowServer
  module Client

    def self.perform_activity(activity)
      if (url = activity.my_user.try(:activity_endpoint))
        response = post(url, activity: activity.serializable_hash)
        raise WorkflowServer::HttpError.new("http request to perform_activity failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.make_decision(decision)
      if (url = decision.my_user.try(:decision_endpoint))
        response = post(url, decision: decision.serializable_hash)
        raise WorkflowServer::HttpError.new("http request to make_decision failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.notify_of(event, notification, error = nil)
      workflow = event.is_a?(WorkflowServer::Models::Workflow) ? event : event.workflow
      notification = "#{workflow.try(:subject_klass)}(#{workflow.try(:subject_id)}):#{event.event_type}(#{event.name}):#{notification}"

      if (url = event.my_user.try(:notification_endpoint))
        params = {notification: notification}
        params.merge!(error: error) if error
        response = post(url, params)
        raise WorkflowServer::HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.post(url, params = {})
      body = WorkflowServer::Helper::HashKeyTransformations.camelize_keys(params).to_json
      ::HTTParty.post(url, body: body, headers: {"Content-Type" => "application/json", "Content-Length" => body.size.to_s})
    end
  end
end
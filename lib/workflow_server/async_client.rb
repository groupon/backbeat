require 'httparty'
require_relative 'helper'

module WorkflowServer
  module AsyncClient
    include WorkflowServer::Logger

    def self.perform_activity(activity)
      if (url = activity.workflow.user.try(:activity_callback_endpoint))
        post(url, activity: activity.serializable_hash)
      end
    end

    def self.make_decision(decision)
      if (url = decision.workflow.user.try(:decision_callback_endpoint))
        post(url, decision: decision.serializable_hash)
      end
    end

    def self.notify_of(event, notification, error = nil)
      workflow = event.is_a?(WorkflowServer::Models::Workflow) ? event : event.workflow
      notification = "#{workflow.try(:subject_klass)}(#{workflow.try(:subject_id)}):#{event.event_type}(#{event.name}):#{notification}"
      if error
        error(notification: notification, error: error)
      else
        info(notification: notification, error: error)
      end

      if (url = workflow.user.try(:notification_endpoint))
        params = {notification: notification}
        params.merge!(error: error) if error
        post(url, params)
      end
    end

    def self.post(url, params = {})
      body = WorkflowServer::Helper::HashKeyTransformations.camelize_keys(params).to_json
      ::HTTParty.post(url, body: body, headers: {"Content-Type" => "application/json", "Content-Length" => body.size.to_s})
    end
  end
end
require 'httparty'

module WorkflowServer
  module AsyncClient

    def self.perform_activity(activity)
      if (url = activity.workflow.user.try(:activity_callback_endpoint))
        post(url, activity: activity)
      end
    end

    def self.make_decision(decision)
      if (url = decision.workflow.user.try(:decision_callback_endpoint))
        post(url, decision: decision)
      end
    end

    def self.notify_of(event, notification, error = nil)
      workflow = event.is_a?(WorkflowServer::Models::Workflow) ? event : event.workflow
      if (url = workflow.user.try(:notification_endpoint))
        params = {notification: "#{workflow.try(:subject_type)}(#{workflow.try(:subject_id)}):#{event.event_type}(#{event.name}):#{notification}"}
        params.merge!(error: error) if error
        post(url, params)
      end
    end

    def self.post(url, params = {})
      body = params.to_json
      #TODO use EventMacine HTTP
      ::HTTParty.post(url, body: body, headers: {"Content-Type" => "application/json", "Content-Length" => body.size.to_s})
    end
  end
end

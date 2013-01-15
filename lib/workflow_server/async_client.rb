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
      if (url = event.workflow.user.try(:notification_endpoint))
        params = {notification: "#{event.workflow.try(:subject_class)}(#{event.workflow.try(:subject_id)}):#{event.name}:#{notification}"}
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

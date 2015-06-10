require 'httparty'
require 'backbeat/client/serializers'

module Backbeat
  module Client
    def self.notify_of(node, message, error = nil)
      user = node.user
      if (url = user.try(:notification_endpoint))
        notification = Client::NotificationSerializer.call(node, message, error)
        response = post(user.notification_endpoint, notification)
        raise HttpError.new("http request to notify_of failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.perform_action(node)
      Instrument.instrument("client_perform_action", { node: node.id, legacy_type: node.legacy_type }) do
        if node.decision?
          make_decision(Client::NodeSerializer.call(node), node.user)
        else
          perform_activity(Client::NodeSerializer.call(node), node.user)
        end
      end
    end

    def self.perform_activity(activity, user)
      if (url = user.try(:activity_endpoint))
        response = post(url, activity: activity.is_a?(Hash) ?  activity : activity.serializable_hash)
        raise HttpError.new("http request to perform_activity failed", response) unless response.code.between?(200, 299)
      end
    end
    private_class_method :perform_activity

    def self.make_decision(decision, user)
      if (url = user.try(:decision_endpoint))
        response = post(url, decision: decision.is_a?(Hash) ?  decision : decision.serializable_hash)
        raise HttpError.new("http request to make_decision failed", response) unless response.code.between?(200, 299)
      end
    end
    private_class_method :make_decision

    def self.post(url, params = {})
      params = params.dup
      body = HashKeyTransformations.camelize_keys(params).to_json
      HTTParty.post(url, body: body, headers: {"Content-Type" => "application/json", "Content-Length" => body.size.to_s})
    rescue
      raise HttpError.new("Could not POST #{url}", nil)
    end
    private_class_method :post
  end
end

require 'httparty'
require 'backbeat/client/serializers'

module Backbeat
  module Client
    def self.notify_of(node, message, error = nil)
      user = node.user
      if url = user.notification_endpoint
        notification = NotificationSerializer.call(node, message, error)
        response = post(url, notification)
        raise HttpError.new("HTTP request for notification failed", response) unless response.code.between?(200, 299)
      end
    end

    def self.perform_action(node)
      Instrument.instrument("client_perform_action", { node: node.id, legacy_type: node.legacy_type }) do
        if node.decision? && node.user.decision_endpoint
          make_decision(NodeSerializer.call(node), node.user)
        else
          perform_activity(NodeSerializer.call(node), node.user)
        end
      end
    end

    def self.perform_activity(activity, user)
      if url = user.activity_endpoint
        response = post(url, { activity: activity })
        raise HttpError.new("HTTP request for activity failed", response) unless response.code.between?(200, 299)
      end
    end
    private_class_method :perform_activity

    def self.make_decision(decision, user)
      if url = user.decision_endpoint
        response = post(url, { decision: decision })
        raise HttpError.new("HTTP request for decision failed", response) unless response.code.between?(200, 299)
      end
    end
    private_class_method :make_decision

    def self.post(url, params = {})
      body = HashKeyTransformations.camelize_keys(params).to_json
      HTTParty.post(url, {
        body: body,
        headers: {
          "Content-Type" => "application/json",
          "Content-Length" => body.size.to_s
        }
      })
    rescue
      raise HttpError.new("Could not POST #{url}", nil)
    end
    private_class_method :post
  end
end

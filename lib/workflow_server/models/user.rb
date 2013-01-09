module WorkflowServer
  module Models
    class User
      include Mongoid::Document
      include Mongoid::Timestamps

      field :decision_callback_endpoint, type: String
      field :activity_callback_endpoint, type: String
      field :notification_endpoint,      type: String

      has_many :workflows
    end
  end
end
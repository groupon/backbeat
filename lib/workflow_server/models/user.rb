require 'uuid'

module WorkflowServer
  module Models
    class User
      include Mongoid::Document
      include Mongoid::Timestamps

      field :client_id,                  type: String
      field :decision_callback_endpoint, type: String
      field :activity_callback_endpoint, type: String
      field :notification_endpoint,      type: String

      has_many :workflows

      index({ client_id: 1 }, { unique: true })

      before_create :assign_client_id

      def assign_client_id
        self.client_id ||= UUID.generate
      end
    end
  end
end
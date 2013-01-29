module WorkflowServer
  module Models
    class User
      include Mongoid::Document
      include Mongoid::Timestamps

      field :_id,                        type: String, default: ->{ UUIDTools::UUID.random_create.to_s }
      field :decision_endpoint,          type: String
      field :activity_endpoint,          type: String
      field :notification_endpoint,      type: String

      has_many :workflows

      validates_presence_of :decision_endpoint, :activity_endpoint, :notification_endpoint

      def serializable_hash(options = {})
        hash = super
        hash.delete("_id")
        hash.merge({ id: id })
      end
    end
  end
end

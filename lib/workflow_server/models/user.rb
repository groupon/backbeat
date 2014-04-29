module WorkflowServer
  module Models
    ##
    # This class represents a client application that consumes Backbeats API.
    class User
      include Mongoid::Document
      include Mongoid::Timestamps

      ##
      # A UUID that identifies the user and doubles as their API token.
      field :_id,                        type: String, default: ->{ UUIDTools::UUID.random_create.to_s }
      ##
      # An HTTP endpoint that is called by Backbeat when it asks the user to make a decision.
      # This field is required.
      field :decision_endpoint,          type: String
      ##
      # An HTTP endpoint that is called by Backbeat when it asks the user to perform an activity.
      # This field is required.
      field :activity_endpoint,          type: String
      ##
      # An HTTP endpoint that is called by Backbeat to provide the user with event notifications for logging.
      # This field is required.
      field :notification_endpoint,      type: String

      field :email,                      type: String  # contact email for this api key
      field :description,                type: String  # some note about this user

      ##
      # A user has a relation to all workflows created by that user.
      # A user can only see workflows that belong to them.
      has_many :workflows, order: {sequence: 1}
      has_many :events, order: {sequence: 1}

      validates_presence_of :decision_endpoint, :activity_endpoint, :notification_endpoint

      ##
      # A method that blacklists certain fields before converting the object to a hash.
      # This method is used by the API to hide unnecessary, private, or sensitive fields from users.
      def serializable_hash(options = {})
        hash = super
        hash.delete("_id")
        hash.merge({ id: id })
        Marshal.load(Marshal.dump(hash))
      end
    end
  end
end

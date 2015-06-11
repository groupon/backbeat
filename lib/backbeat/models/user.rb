module Backbeat
  class User < ActiveRecord::Base
    self.primary_key = :id

    has_many :workflows
    has_many :nodes
    belongs_to :user

    validates :decision_endpoint, presence: true
    validates :activity_endpoint, presence: true
    validates :notification_endpoint, presence: true
  end
end

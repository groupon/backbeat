module Backbeat
  class User < ActiveRecord::Base
    has_many :workflows
    has_many :nodes
    belongs_to :user

    validates :activity_endpoint, presence: true
    validates :notification_endpoint, presence: true
  end
end

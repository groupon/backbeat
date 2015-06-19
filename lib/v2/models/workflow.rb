require 'v2/models/child_queries'

module V2
  class Workflow < ActiveRecord::Base
    self.primary_key = :id

    belongs_to :user
    has_many :nodes
    serialize :subject, JSON

    validates :subject, presence: true
    validates :decider, presence: true
    validates :user_id, presence: true

    include ChildQueries

    def parent
      nil
    end

    def children
      nodes.where(parent_id: nil)
    end

    def workflow_id
      id
    end

    def deactivated?
      false
    end

    def complete!
      update_attributes(complete: true)
    end

    def pause!
      update_attributes(paused: true)
    end

    def resume!
      update_attributes(paused: false)
    end
  end
end

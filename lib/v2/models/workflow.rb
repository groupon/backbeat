require 'v2/models/child_status_methods'

module V2
  class Workflow < ActiveRecord::Base
    include UUIDSupport

    uuid_column :uuid

    belongs_to :user
    has_many :nodes
    serialize :subject, JSON

    validates :subject, presence: true
    validates :decider, presence: true
    validates :user_id, presence: true

    def self.find_or_create_from_v1(v1_workflow, v2_user_id)
      v2_workflow = V2::Workflow.find_by_uuid(v1_workflow.id)
      return v2_workflow if v2_workflow

      V2::Workflow.create!(
        uuid: v1_workflow.id,
        name: v1_workflow.name,
        decider: v1_workflow.decider,
        subject: v1_workflow.subject,
        user_id: v2_user_id,
        complete: v1_workflow.status == :complete
      )
    end

    include SharedNodeMethods

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
  end
end

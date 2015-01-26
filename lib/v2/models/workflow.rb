class V2::Workflow < ActiveRecord::Base
  self.primary_key = 'id'

  belongs_to :user
  has_many :nodes
  serialize :subject, JSON

  validates :subject, presence: true
  validates :decider, presence: true
  validates :user_id, presence: true

  def parent
    nil
  end

  def children
    nodes.where(parent_id: nil)
  end

  def workflow_id
    id
  end

  def all_children_ready?
    !children.where(current_server_status: :pending).exists?
  end

  def not_complete_children
    children.where("current_server_status != 'complete'")
  end

  def all_children_complete?
    !not_complete_children.exists?
  end
end

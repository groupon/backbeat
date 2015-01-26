class V2::Workflow < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :user
  has_many :nodes
  serialize :subject, JSON

  validates :workflow_type, presence: true
  validates :subject, presence: true
  validates :decider, presence: true
  validates :initial_signal, presence: true
  validates :user_id, presence: true

  def name
    workflow_type
  end

  def children
    nodes.where(workflow_id: id, parent_id: nil)
  end

  def children_ready_to_start
    ready_decision = children.where(current_server_status: :ready).first
    if other_decision_running?(ready_decision)
      []
    else
      [ready_decision]
    end
  end

  def other_decision_running?(decision)
    children.where("seq < #{decision.seq} AND current_server_status <> 'complete'").exists?
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

  def serializable_hash(options = {})
    self.attributes
  end
end

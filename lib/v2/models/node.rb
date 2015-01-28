require 'enumerize'

class V2::Node < ActiveRecord::Base
  extend ::Enumerize

  self.primary_key = 'id'

  default_scope { order("seq asc") }

  belongs_to :user
  belongs_to :workflow
  has_many :children, class_name: "V2::Node", foreign_key: "parent_id"
  belongs_to :parent_node, inverse_of: :children, class_name: "V2::Node", foreign_key: "parent_id"
  has_one :client_node_detail
  has_one :node_detail
  has_many :status_changes

  validates :mode, presence: true
  validates :current_server_status, presence: true
  validates :current_client_status, presence: true
  validates :name, presence: true
  validates :fires_at, presence: true
  validates :user_id, presence: true

  enumerize :mode, in: [:blocking, :non_blocking, :fire_and_forget]

  enumerize :current_server_status, in: [:pending,
                                         :ready,
                                         :started,
                                         :sent_to_client,
                                         :recieved_from_client,
                                         :processing_children,
                                         :complete,
                                         :errored,
                                         :retrying]

  enumerize :current_client_status, in: [:pending,
                                         :ready,
                                         :received,
                                         :processing,
                                         :complete,
                                         :errored]

  before_create do
    self.seq ||= ActiveRecord::Base.connection.execute("SELECT nextval('nodes_seq_seq')").first["nextval"]
    self.workflow_id ||= parent.workflow_id
  end

  delegate :retries_remaining, :legacy_type, to: :node_detail
  delegate :complete?, :processing_children?, :ready?, to: :current_server_status
  delegate :subject, :decider, to: :workflow

  def parent=(node)
    self.parent_id = node.id if node.is_a?(V2::Node)
  end

  def parent
    parent_node || workflow
  end

  def all_children_ready?
    !children.where(current_server_status: :pending).exists?
  end

  def not_complete_children
    children.where("current_server_status != 'complete'")
  end

  def all_children_complete?
    !not_complete_children.where("mode != 'fire_and_forget'").exists?
  end

  def blocking?
    mode.to_sym == :blocking
  end

  def mark_retried!
    node_detail.update_attributes!(retries_remaining: retries_remaining - 1)
  end
end

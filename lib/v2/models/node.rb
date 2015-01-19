require 'enumerize'

class V2::Node < ActiveRecord::Base
  extend ::Enumerize

  self.primary_key = 'id'

  default_scope { order("seq asc") }

  belongs_to :workflow
  belongs_to :user
  has_many :children, class_name: "V2::Node", foreign_key: "parent_id"
  belongs_to :parent, inverse_of: :children, class_name: "V2::Node", foreign_key: "parent_id"
  has_one :client_node_detail
  has_one :node_detail
  has_many :status_changes

  validates :mode, presence: true
  validates :current_server_status, presence: true
  validates :current_client_status, presence: true
  validates :name, presence: true
  validates :fires_at, presence: true
  validates :workflow_id, presence: true
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

  VALID_STATE_CHANGES = {
    current_client_status: {
      pending: [:ready, :errored],
      ready: [:received, :errored],
      received: [:processing, :complete, :errored],
      processing: [:complete],
      errored: [:received],
      complete: [:complete]
    },
    current_server_status: {
      pending: [:ready, :errored],
      ready: [:started, :errored],
      started: [:sent_to_client, :errored],
      sent_to_client: [:processing_children, :recieved_from_client, :errored],
      processing_children: [:complete],
      errored: [:retrying],
      retrying: [:sent_to_client],
      complete: [:complete]
    }
  }

  before_create do
    self.seq ||= ActiveRecord::Base.connection.execute("SELECT nextval('nodes_seq_seq')").first["nextval"]
  end

  delegate :retries_remaining, :legacy_type, to: :node_detail

  def all_children_ready?
    !children.where(current_server_status: :pending).exists?
  end

  def not_complete_children
    children.where("current_server_status != 'complete'")
  end

  def children_ready_to_start
    children.where(current_server_status: :ready)
  end

  def all_children_complete?
    !not_complete_children.where("mode != 'fire_and_forget'").exists?
  end

  def current_parent
    parent || workflow
  end

  def blocking?
    mode.to_sym == :blocking
  end

  def started?
    current_server_status.to_sym == :started
  end

  def validate(record)
    unless record.name.starts_with? 'X'
      record.errors[:name] << 'Need a name starting with X please!'
    end
  end

  def update_status(statuses)
    [:current_client_status, :current_server_status].each do |status_type|
      new_status = statuses[status_type]
      next unless new_status
      if valid_status_change?(new_status, status_type)
        status_changes.create!(
          from_status: self.send(status_type),
          to_status: new_status,
          status_type: status_type
        )
      else
        raise V2::InvalidEventStatusChange.new(
          "Cannot transition #{status_type} to #{new_status} from #{self.send(status_type)}"
        )
      end
    end
    update_attributes!(statuses)
  end

  def mark_retried!
    node_detail.update_attributes!(retries_remaining: retries_remaining - 1)
  end

  private

  def valid_status_change?(new_status, status_type)
    valid_state_changes = VALID_STATE_CHANGES[status_type.to_sym][self.send(status_type).to_sym]
    new_status && valid_state_changes.include?(new_status)
  end
end

require 'enumerize'

class V2::Node < ActiveRecord::Base
  extend ::Enumerize

  self.primary_key = 'id'
  belongs_to :workflow
  belongs_to :user
  has_many :children,  class_name: "V2::Node", foreign_key: "parent_id"
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

  VALID_SERVER_STATE_CHANGES = {
    pending: :ready,
    ready: :started,
    started: :sent_to_client,
    sent_to_client: :recieved_from_client,
    processing_children: :complete,
    errored: :retrying,
    retrying: :sent_to_client
  }

  enumerize :current_client_status, in: [:pending,
                                         :ready,
                                         :received,
                                         :processing,
                                         :complete,
                                         :errored]

  VALID_CLIENT_STATE_CHANGES = {
    pending: :ready,
    ready: :received,
    received: [:processing, :complete],
    processing: :complete
  }

  before_create do
    self.seq ||= ActiveRecord::Base.connection.execute("SELECT nextval('nodes_seq_seq')").first["nextval"]
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

  def current_parent
    parent || workflow
  end

  def validate(record)
    unless record.name.starts_with? 'X'
      record.errors[:name] << 'Need a name starting with X please!'
    end
  end

  def update_status(statuses)
    [:current_client_status, :current_server_status].each do |status_type|
      new_status = statuses[status_type]
      current_status = self.send(status_type)
      if new_status && new_status.to_s != current_status
        status_changes.create!(
          from_status: current_status,
          to_status: new_status,
          status_type: status_type
        )
      end
    end
    update_attributes!(statuses)
  end
end

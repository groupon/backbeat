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

  STATUS_CHANGE_FIELDS = [:current_server_status, :current_client_status]

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

  def update_attributes!(args)
    args.each do |arg|
      status_type = arg[0]
      current_status = arg[1]
      previous_status = self.attributes[status_type.to_s]

      if current_status != previous_status && STATUS_CHANGE_FIELDS.include?(status_type)
        V2::StatusChange.create!(node: self, from_status: previous_status, to_status: current_status, status_type: status_type)
      end
    end

    super(args)
  end
end

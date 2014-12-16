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

  def current_parent
    parent || workflow
  end

  validates :mode, presence: true
  validates :current_server_status, presence: true
  validates :current_client_status, presence: true
  validates :name, presence: true
  validates :fires_at, presence: true
  validates :workflow_id, presence: true
  validates :user_id, presence: true



  enumerize :mode, in: [:blocking, :nonblocking, :fire_and_forget]
  enumerize :current_server_status, in: [:pending,
                                         :ready,
                                         :started,
                                         :sent_to_client,
                                         :recieved_from_client,
                                         :processing_children,
                                         :complete,
                                         :errored,
                                         :retry]
  enumerize :current_client_status, in: [:pending, :ready, :processing, :complete, :errored ]

  before_create do
    self.seq ||= ActiveRecord::Base.connection.execute("SELECT nextval('nodes_seq_seq')").first["nextval"]
  end

end

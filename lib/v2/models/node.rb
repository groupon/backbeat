require 'enumerize'
require 'v2/models/child_status_methods'

module V2
  class Node < ActiveRecord::Base
    extend ::Enumerize
    include UUIDSupport

    uuid_column :uuid

    default_scope { order("id asc") }

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
    validates :workflow_id, presence: true

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

    delegate :retries_remaining, :legacy_type, to: :node_detail
    delegate :complete?, :processing_children?, :ready?, to: :current_server_status
    delegate :subject, :decider, to: :workflow

    include ChildStatusMethods

    def parent=(node)
      self.parent_id = node.id if node.is_a?(V2::Node)
    end

    def parent
      parent_node || workflow
    end

    def blocking?
      mode.to_sym == :blocking
    end

    def mark_retried!
      node_detail.update_attributes!(retries_remaining: retries_remaining - 1)
    end
  end
end

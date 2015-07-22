require 'enumerize'
require 'backbeat/models/child_queries'

module Backbeat
  class Node < ActiveRecord::Base
    extend Enumerize

    default_scope { order("seq asc") }

    belongs_to :user
    belongs_to :workflow
    has_many :children, class_name: "Backbeat::Node", foreign_key: "parent_id", dependent: :destroy
    belongs_to :parent_node, inverse_of: :children, class_name: "Backbeat::Node", foreign_key: "parent_id"
    has_one :client_node_detail, dependent: :destroy
    has_one :node_detail, dependent: :destroy
    has_many :status_changes, dependent: :destroy

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
                                           :deactivated,
                                           :retrying,
                                           :paused]

    enumerize :current_client_status, in: [:pending,
                                           :ready,
                                           :received,
                                           :processing,
                                           :complete,
                                           :errored]

    delegate :retries_remaining, :retry_interval, :legacy_type, :legacy_type=, to: :node_detail
    delegate :data, to: :client_node_detail, prefix: :client
    delegate :metadata, to: :client_node_detail, prefix: :client
    delegate :complete?, :processing_children?, :ready?, to: :current_server_status
    delegate :subject, :decider, to: :workflow
    delegate :name, to: :workflow, prefix: :workflow

    scope :incomplete, -> { where("(current_server_status <> 'complete' OR current_client_status <> 'complete')") }
    scope :active, -> { where("current_server_status <> 'deactivated'") }

    before_create do
      self.seq ||= ActiveRecord::Base.connection.execute("SELECT nextval('nodes_seq_seq')").first["nextval"]
    end

    include ChildQueries

    def parent=(node)
      self.parent_id = node.id if node.is_a?(Node)
    end

    def parent
      parent_node || workflow
    end

    def blocking?
      mode.to_sym == :blocking
    end

    def deactivated?
      current_server_status.to_sym == :deactivated
    end

    def mark_retried!
      node_detail.update_attributes!(retries_remaining: retries_remaining - 1)
    end

    def perform_client_action?
      legacy_type.to_sym != :flag
    end

    def decision?
      legacy_type.to_sym == :decision
    end

    PERFORMED_STATES = [:sent_to_client, :complete, :processing_children]

    def already_performed?
      PERFORMED_STATES.include?(current_server_status.to_sym)
    end

    def paused?
      Workflow.where(id: workflow_id, paused: true).exists?
    end

    def touch!
      # maybe add status conditions, but i don't think it's necessary
      node_detail.update_attributes!(complete_by: should_complete_by)
    end

    private
    def should_complete_by
      timeout = client_data.try(:fetch, "timeout", Backbeat::Config.options[:default_client_timeout]) # This can be a user level setting as well
      if timeout
        Time.now + timeout
      end
    end
  end
end

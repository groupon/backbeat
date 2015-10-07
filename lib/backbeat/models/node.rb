# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
    has_many :child_links, class_name: "Backbeat::Node", foreign_key: "parent_link_id"
    belongs_to :parent_link, inverse_of: :child_links, class_name: "Backbeat::Node", foreign_key: "parent_link_id"
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
      legacy_type.try(:to_sym) != :flag
    end

    def decision?
      legacy_type.try(:to_sym) == :decision
    end

    PERFORMED_STATES = [:sent_to_client, :complete, :processing_children]

    def already_performed?
      PERFORMED_STATES.include?(current_server_status.to_sym)
    end

    def paused?
      Workflow.where(id: workflow_id, paused: true).exists?
    end

    def touch!
      node_detail.update_attributes!(complete_by: should_complete_by)
    end

    def nodes_to_notify
      [parent, parent_link].compact
    end

    def all_children_complete?
      direct_children_complete? && child_links_complete?
    end

    private

    def should_complete_by
      timeout = client_data.fetch("timeout", Backbeat::Config.options[:default_client_timeout])
      if timeout
        Time.now + timeout
      end
    end

    def child_links_complete?
      child_links.all? { |node| node.complete? }
    end
  end
end

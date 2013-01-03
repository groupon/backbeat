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

module Backbeat
  class Server
    extend Logging

    def self.create_workflow(params, user)
      find_workflow(params, user) || Workflow.create!(
        name: params[:workflow_type] || params[:name],
        subject: params[:subject],
        decider: params[:decider],
        user_id: user.id,
        migrated: true
      )
    rescue ActiveRecord::RecordNotUnique => e
      find_workflow(params, user)
    end

    def self.find_workflow(params, user)
      Workflow.where(
        name: params[:workflow_type] || params[:name],
        subject: params[:subject].to_json,
        user_id: user.id
      ).first
    end

    def self.signal(workflow, params)
      raise WorkflowComplete if workflow.complete?
      node = add_node(
        workflow.user,
        workflow,
        params.merge(
          current_server_status: :ready,
          current_client_status: :ready,
          legacy_type: 'decision',
          mode: :blocking
        )
      )
      node
    end

    def self.add_node(user, parent_node, params)
      Node.transaction do
        options = params[:options] || params
        node = Node.create!(
          mode: params.fetch(:mode, :blocking).to_sym,
          current_server_status: params[:current_server_status] || :pending,
          current_client_status: params[:current_client_status] || :pending,
          name: params[:name],
          fires_at: params[:fires_at] || Time.now - 1.second,
          parent: parent_node,
          workflow_id: parent_node.workflow_id,
          user_id: user.id,
          parent_link_id: options[:parent_link_id]
        )
        ClientNodeDetail.create!(
          node: node,
          metadata: options[:metadata] || {},
          data: options[:client_data] || {}
        )
        NodeDetail.create!(
          node: node,
          legacy_type: params[:legacy_type],
          retry_interval: params[:retry_interval],
          retries_remaining: params[:retry]
        )
        node
      end
    end

    def self.resume_workflow(workflow)
      workflow.resume!
      workflow.nodes.where(current_server_status: :paused).each do |node|
        StateManager.transition(node, current_server_status: :started)
        fire_event(Events::StartNode, node)
      end
    end

    def self.fire_event(event, node, scheduler = event.scheduler)
      return if node.deactivated?
      scheduler.call(event, node)
    end
  end
end

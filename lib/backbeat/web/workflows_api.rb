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

require 'grape'
require 'backbeat/errors'
require 'backbeat/server'
require 'backbeat/models/workflow'
require 'backbeat/web/helpers/current_user_helper'
require 'backbeat/search/workflow_search'

module Backbeat
  module Web
    class WorkflowsApi < Grape::API
      version 'v2', using: :path

      helpers CurrentUserHelper

      helpers do
        def find_workflow
          Workflow.where(user_id: current_user.id).find(params[:id])
        end
      end

      resource 'workflows' do
        post "/" do
          wf = Server.create_workflow(params, current_user)
          if wf.valid?
            wf
          else
            raise InvalidParameters, wf.errors.to_hash
          end
        end

        get "/" do
          subject = params[:subject].is_a?(String) ? params[:subject] : params[:subject].to_json
          Workflow.where(
            migrated: true,
            user_id: current_user.id,
            subject: subject,
            decider: params[:decider],
            name: params[:workflow_type] || params[:name]
          ).first!
        end

        get "/names" do
          Workflow.select(:name).distinct.map { |item| item["name"] }
        end

        get "/search" do
          Search::WorkflowSearch.new(params).result
        end

        post "/:id/signal" do
          workflow = find_workflow
          signal = Server.signal(workflow, params)
          Server.fire_event(Events::ScheduleNextNode, workflow)
          signal
        end

        post "/:id/signal/:name" do
          workflow = find_workflow
          signal = Server.signal(workflow, params)
          Server.fire_event(Events::ScheduleNextNode, workflow)
          signal
        end

        put "/:id/complete" do
          workflow = find_workflow
          workflow.complete!
          { success: true }
        end

        put "/:id/pause" do
          workflow = find_workflow
          workflow.pause!
          { success: true }
        end

        put "/:id/resume" do
          workflow = find_workflow
          Server.resume_workflow(workflow)
          { success: true }
        end

        get "/:id" do
          find_workflow
        end

        get "/:id/tree" do
          workflow = find_workflow
          WorkflowTree.to_hash(workflow)
        end

        get "/:id/tree/print" do
          workflow = find_workflow
          { print: WorkflowTree.to_string(workflow) }
        end

        get "/:id/children" do
          find_workflow.children
        end

        VALID_NODE_FILTERS = [:current_server_status, :current_client_status]

        get "/:id/nodes" do
          search_params = params.slice(*VALID_NODE_FILTERS).to_hash
          find_workflow.nodes.where(search_params).map { |node| Client::NodeSerializer.call(node) }
        end
      end
    end
  end
end

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

        get "/search" do
          Search::WorkflowSearch.new(params).result
        end

        get "/:id" do
          find_workflow
        end

        get "/" do
          subject = params[:subject].is_a?(String) ? params[:subject] : params[:subject].to_json
          Workflow.where(
            migrated: true,
            user_id: current_user.id,
            subject: subject,
            decider: params[:decider],
            name: params[:workflow_type]
          ).first!
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

require "grape"
require "v2/server"
require "v2/models/workflow"
require "workflow_server/errors"
require "api/helpers/current_user_helper"

module V2
  module Api
    class WorkflowsApi < Grape::API
      helpers ::Api::CurrentUserHelper
      version 'v2', using: :path

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
            raise WorkflowServer::InvalidParameters, wf.errors.to_hash
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
        end

        put "/:id/pause" do
          workflow = find_workflow
          workflow.pause!
        end

        put "/:id/resume" do
          workflow = find_workflow
          Server.resume_workflow(workflow)
        end

        get "/:id" do
          find_workflow
        end

        get "/" do
          Workflow.where(
            migrated: true,
            user_id: current_user.id,
            decider: params[:decider],
            name: params[:workflow_type],
            subject: params[:subject]
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
          search_params = params.slice(*VALID_NODE_FILTERS)
          find_workflow.nodes.where(search_params).map{|node| V2::Client::NodeSerializer.call(node)}
        end
      end
    end
  end
end

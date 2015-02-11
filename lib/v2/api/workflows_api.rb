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
          params[:user] = current_user
          wf = Server.create_workflow(params, current_user)
          if wf.valid?
            wf
          else
            raise WorkflowServer::InvalidParameters, wf.errors.to_hash
          end
        end

        post "/:id/signal/:name" do
          workflow = find_workflow
          raise V2::WorkflowComplete if workflow.complete?
          node = Server.add_node(
            current_user,
            workflow,
            params.merge(
              current_server_status: :ready,
              current_client_status: :ready,
              legacy_type: 'signal',
              mode: :blocking
            )
          )
          Server.fire_event(Events::ScheduleNextNode, workflow)
          node
        end

        put "/:id/complete" do
          workflow = find_workflow
          workflow.complete!
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

        put "/:id/deactivated" do
          workflow = find_workflow

          Server.fire_event(Events::DeactivateNode, workflow)
        end
      end
    end
  end
end

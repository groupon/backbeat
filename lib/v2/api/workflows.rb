require "grape"
require "v2/server"
require "v2/models/node"
require "workflow_server/errors"
require "api/helpers/current_user_helper"

module V2
  module Api
    class Workflows < Grape::API
      helpers ::Api::CurrentUserHelper

      resource 'workflows' do
        post "/" do
          params[:user] = current_user
          wf = V2::Server.create_workflow(params, current_user)
          if wf.valid?
            wf
          else
            raise WorkflowServer::InvalidParameters, wf.errors.to_hash
          end
        end

        post "/:id/signal/:name" do
          node = nil
          workflow = nil
          workflow = V2::Workflow.find(params[:id])
          node = V2::Server.add_node(current_user,
                                     workflow,
                                     params.merge('legacy_type' => :signal,
                                                  'mode' => :blocking),
                                                  nil)

          V2::Server.fire_event(V2::Server::MarkSignalReady, node)
          node
        end
      end
    end
  end
end

require "grape"
require "v2/server"
require "v2/models/node"
require "workflow_server/errors"
require "api/helpers/current_user_helper"

module V2
  module Api
    module EventEndpoints

      STATUS_EVENT_MAP = {
        deciding_complete: Events::ClientComplete,
        deciding: Events::ClientProcessing,
        completed: Events::ClientComplete,
        errored: Events::ClientError,
        deactivated: Events::DeactivateNode
      }

      def event_api
        helpers ::Api::CurrentUserHelper

        helpers do
          def find_node
            query = { user_id: current_user.id }
            query[:workflow_id] = params[:workflow_id] if params[:workflow_id]
            Node.where(query).find(params[:id])
          end
        end

        resource 'events' do
          get "/:id" do
            find_node
          end

          put "/:id/status/:new_status" do
            node = find_node
            new_status = params[:new_status].to_sym
            Server.fire_event(STATUS_EVENT_MAP[new_status], node)
          end

          put "/:id/restart" do
            node = find_node
            Server.fire_event(Events::RetryNode, node, Schedulers::PerformEvent)
            {success: true}
          end

          post "/:id/decisions" do
            if params[:args] && !params[:args].is_a?(Hash)
              raise WorkflowServer::InvalidParameters, "args parameter is invalid"
            end
            if params[:args][:decisions].nil? || params[:args][:decisions].empty?
              raise WorkflowServer::InvalidParameters, "args must include a 'decisions' parameter"
            end
            node = find_node
            params[:args][:decisions].each do |dec|
              node_to_add = dec.dup
              node_to_add[:options] = {}
              node_to_add[:options][:metadata] = node_to_add[:metadata]
              node_to_add[:options][:client_data] = node_to_add[:client_data]
              node_to_add[:legacy_type] = node_to_add[:type]
              Server.add_node(current_user, node, node_to_add)
            end
            {success: true}
          end

          put "/:id/status/:new_status" do
            node = find_node
            new_status = params[:new_status].to_sym
            Server.fire_event(STATUS_MAP[new_status], node)
          end
        end
      end
    end

    class EventsApi < Grape::API
      extend EventEndpoints
      version 'v2', using: :path
      event_api
    end

    class WorkflowEventsApi < Grape::API
      extend EventEndpoints
      version 'v2', using: :path
      resource 'workflows/:workflow_id' do
        event_api
      end
    end
  end
end

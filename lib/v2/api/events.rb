require "grape"
require "v2/server"
require "v2/models/node"
require "workflow_server/errors"
require "api/helpers/current_user_helper"

module V2
  module Api
    module EventEndpoints
      def define_routes
        helpers ::Api::CurrentUserHelper

        resource 'events' do
          put "/:id/restart" do
            node = V2::Node.find(params[:id])
            V2::Server.fire_event(V2::Server::RetryNode, node)
            {success: true}
          end

          post "/:id/decisions" do
            if params[:args] && !params[:args].is_a?(Hash)
              raise WorkflowServer::InvalidParameters, "args parameter is invalid"
            end
            if params[:args][:decisions].nil? || params[:args][:decisions].empty?
              raise WorkflowServer::InvalidParameters, "args must include a 'decisions' parameter"
            end
            node = V2::Node.find(params[:id])
            params[:args][:decisions].each do |dec|
              node_to_add = dec.dup
              node_to_add['options'] = {}
              node_to_add['options']['meta_data'] = node_to_add["meta_data"]
              node_to_add['options']['client_data'] = node_to_add["client_data"]
              node_to_add[:legacy_type] = node_to_add['type']
              V2::Server.add_node(current_user, node, node_to_add)
            end
            {success: true}
          end

          put "/:id/status/:new_status" do
            if params[:args] && !params[:args].is_a?(Hash)
              raise WorkflowServer::InvalidParameters, "args parameter is invalid"
            end
            status_map = {
              deciding_complete: V2::Server::ClientComplete,
              deciding: V2::Server::ClientProcessing,
              completed: V2::Server::ClientComplete,
              errored: V2::Server::ClientError,
              resolved: V2::Server::ClientResolved
            }
            node = V2::Node.find(params[:id])
            V2::Server.fire_event(status_map[params[:new_status].to_sym], node)
          end
        end
      end

      def self.extended(klass)
        klass.class_eval do
          define_routes
        end
      end
    end

    class Events < Grape::API
      extend EventEndpoints
    end

    class WorkflowEvents < Grape::API
      extend EventEndpoints
    end
  end
end

require 'grape'
require 'backbeat/errors'
require 'backbeat/server'
require 'backbeat/models/node'
require 'backbeat/web/helpers/current_user_helper'

module Backbeat
  module Web
    module EventEndpoints

      CLIENT_EVENTS = {
        deciding: Events::ClientProcessing,
        processing: Events::ClientProcessing,
        deciding_complete: Events::ClientComplete,
        completed: Events::ClientComplete,
        errored: Events::ClientError,
        deactivated: Events::DeactivatePreviousNodes
      }

      def event_api
        helpers CurrentUserHelper

        helpers do
          def find_node
            query = { user_id: current_user.id }
            query[:workflow_id] = params[:workflow_id] if params[:workflow_id]
            Node.where(query).find(params[:id])
          end

          def validate(params, param, type, message)
            value = params[param] || params.fetch(:args, {})[param]
            unless value.is_a?(type)
              raise InvalidParameters, message
            end
            value
          end
        end

        resource 'events' do
          get "/:id" do
            find_node
          end

          put "/:id/status/:new_status" do
            node = find_node
            node.touch!
            new_status = params[:new_status].to_sym
            event_type = CLIENT_EVENTS[new_status]
            response = params[:response] || params[:args]
            event = response ? event_type.new(response) : event_type
            Server.fire_event(event, node)
            { success: true }
          end

          put "/:id/deactivate" do
            node = find_node
            Server.fire_event(Events::DeactivatePreviousNodes, node, Schedulers::PerformEvent)
            { success: true }
          end

          put "/:id/restart" do
            node = find_node
            Server.fire_event(Events::RetryNode, node, Schedulers::PerformEvent)
            { success: true }
          end

          put "/:id/reset" do
            node = find_node
            Server.fire_event(Events::ResetNode, node)
            { success: true }
          end

          post "/:id/decisions" do
            decisions = validate(params, :decisions, Array, "Params must include a 'decisions' param")
            node = find_node
            decisions.each do |dec|
              node_to_add = dec.merge({ legacy_type: dec[:type] })
              Server.add_node(current_user, node, node_to_add)
            end
            { success: true }
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

require 'grape'
require "service-discovery"
require "workflow_server/logger"
require "api/helpers/current_user_helper"
require "api/helpers/workflow_helper"
require "api/helpers/service_discovery_response_creator"

module Api
  class Events < Grape::API
    include WorkflowServer::Logger
    extend ServiceDiscovery::Description::Dsl

    helpers CurrentUserHelper
    helpers WorkflowHelper

    helpers do
      def find_event(params, event_type = nil)
        event = nil
        event_id = params[:id]
        workflow_id = params[:workflow_id]
        if workflow_id
          wf = find_workflow(workflow_id)
          event_type ||= :events #all events
          event = wf.__send__(event_type).find(event_id)
          raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found" unless event
        else
          event = WorkflowServer::Models::Event.find(event_id)
          unless event && event.my_user == current_user
            raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found"
          end
        end
        event
      end
    end

    # Events can be reached using two url's
    # 1) as a subresource /workflows/<workflow_id>/events/<id>
    # 2) or as a top level resource /events/<id>
    # This proc here is the general declaration that is at the end consumed by both the above endpoints.
    EventSpecification = Proc.new do |full_url = true|
      desc "Get the event identified by the id.", {
        action_descriptor: action_description(:get_event) do |get_event|
          get_event.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          get_event.response do |event|
            ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Event, event)
          end
        end
      }
      get "/:id" do
        find_event(params)
      end

      desc "Restart a failed activity or decision.", {
        action_descriptor: action_description(:restart_event) do |restart_event|
          restart_event.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
        end
      }
      put "/:id/restart" do
        if Backbeat.v2?
          node = V2::Node.find(params[:id])
          V2::Server.fire_event(V2::Server::RetryNode, node)
        else
          e = find_event(params)
          e.restart
        end
        {success: true}
      end

      # TODO - make a more generic endpoint to return the history
      desc "Get all the decisions that have occurred in the past based off this decision", {
        action_descriptor: action_description(:history_decisions) do |history_decisions|
          history_decisions.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          history_decisions.response do |response|
            response.array(:decisions) do |event_object|
              event_object.object do |object|
                ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Decision, object)
              end
            end
          end
        end
      }
      get "/:id/history_decisions" do
        event = find_event(params)
        event.past_decisions.where(:inactive.ne => true)
      end

      desc "Get the event tree as a hash.", {
        action_descriptor: action_description(:get_event_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          tree.response do |response|
            ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Event, response, [:id, :type, :name, :status])
            response.array :children do |children|
              children.object do |child|
                ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Event, child, [:id, :type, :name, :status])
              end
            end
          end
        end
      }
      get "/:id/tree" do
        e = find_event(params)
        e.tree
      end

      desc "Get the event tree in a pretty print color encoded string format.", {
        action_descriptor: action_description(:print_event_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          tree.response do |response|
            response.string :print, description: "the event tree in a color coded string format."
          end
        end
      }
      get "/:id/tree/print" do
        e = find_event(params)
        {print: e.tree_to_s}
      end

      desc "Add new decisions to an event.", {
        action_descriptor: action_description(:decisions) do |decisions|
          decisions.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity or decision id', required: true, location: 'url'
          end
        end
      }
      post "/:id/decisions" do
        raise WorkflowServer::InvalidParameters, "args parameter is invalid" if params[:args] && !params[:args].is_a?(Hash)
        raise WorkflowServer::InvalidParameters, "args must include a 'decisions' parameter" if params[:args][:decisions].nil? || params[:args][:decisions].empty?
        if Backbeat.v2?
          node = V2::Node.find(params[:id])
          params[:args][:decisions].each do |dec|
            node_to_add = dec.dup
            node_to_add['options'] = {}
            node_to_add['options']['meta_data'] = node_to_add["meta_data"]
            node_to_add['options']['client_data'] = node_to_add["client_data"]
            V2::Server.add_node(current_user,
                                node.workflow,
                                node_to_add.merge('legacy_type' => node_to_add['type']),
                                node)
          end
        else
          event = find_event(params)
          event.add_decisions(params[:args][:decisions])
        end
        {success: true}
      end

      desc "Update the status on an event (use this endpoint for deciding, deciding_complete, completed, errored).", {
        action_descriptor: action_description(:change_status) do |change_status|
          change_status.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity or decision id', required: true, location: 'url'
          end
        end
      }
      put "/:id/status/:new_status" do
        raise WorkflowServer::InvalidParameters, "args parameter is invalid" if params[:args] && !params[:args].is_a?(Hash)
        if Backbeat.v2?
          status_map = {deciding_complete: V2::Server::ClientComplete,
                        deciding:  V2::Server::ClientProcessing,
                        completed: V2::Server::ClientComplete,
                        errored:  V2::Server::ClientError,
                        resolved:  V2::Server::ClientResolved}
          node = V2::Node.find(params[:id])
          V2::Server.fire_event(status_map[params[:new_status].to_sym], node)
        else
          event = find_event(params)
          args = params[:args] || {}
          event.change_status(params[:new_status], args.with_indifferent_access)
          {success: true}
        end
      end

      desc "Run a nested activity from inside an activity.", {
        action_descriptor: action_description(:run_activity) do |activity|
          activity.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity id', required: true, location: 'url'
          end
          activity.parameters do |parameters|
            parameters.object(:sub_activity, description: "Define the nested activity.", location: 'body') do |sub_activity|
              ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Activity, sub_activity, [:name, :client_data, :mode, :always, :retry, :retry_interval, :time_out])
            end
          end
        end
      }
      params do
        requires :sub_activity, type: Hash, desc: 'sub activity param cannot be empty'
      end
      put "/:id/run_sub_activity" do
        event = find_event(params, :activities)
        sub_activity = event.run_sub_activity(params[:sub_activity] || {})
        if sub_activity.try(:blocking?)
          header("WAIT_FOR_SUB_ACTIVITY", "true")
        end
        sub_activity
      end
    end

    resource 'workflows' do
      segment '/:workflow_id' do
        resource 'events' do
          EventSpecification.call
        end
      end
    end

    resource "events" do
      EventSpecification.call(false)
    end
  end
end

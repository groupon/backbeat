require 'grape'
require "service-discovery"
require "workflow_server/logger"
require "api/api_helpers"

module Api
  class Events < Grape::API
    include WorkflowServer::Logger
    extend ServiceDiscovery::Description::Dsl

    helpers ApiHelpers

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
            ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, event)
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
        e = find_event(params)
        e.restart
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
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Decision, object)
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
            ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, response, [:id, :type, :name, :status])
            response.array :children do |children|
              children.object do |child|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, child, [:id, :type, :name, :status])
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
        event = find_event(params)
        event.add_decisions(params[:args][:decisions])
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
        event = find_event(params)
        args = params[:args] || {}
        event.change_status(params[:new_status], args.with_indifferent_access)
        {success: true}
      end

      desc "Run a nested activity from inside an activity.", {
        action_descriptor: action_description(:run_activity) do |activity|
          activity.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity id', required: true, location: 'url'
          end
          activity.parameters do |parameters|
            parameters.object(:sub_activity, description: "Define the nested activity.", location: 'body') do |sub_activity|
              ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Activity, sub_activity, [:name, :client_data, :mode, :always, :retry, :retry_interval, :time_out])
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

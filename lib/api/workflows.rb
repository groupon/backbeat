require "grape"
require "service-discovery"
require "workflow_server/logger"
require "api/helpers/current_user_helper"
require "api/helpers/workflow_helper"
require "api/helpers/service_discovery_response_creator"
require 'migration/workers/signal_delegate'

module Api
  class Workflows < Grape::API
    include WorkflowServer::Logger
    extend ServiceDiscovery::Description::Dsl

    helpers CurrentUserHelper
    helpers WorkflowHelper

    helpers do
      def workflow_status(workflow)
        workflow_status = workflow.status

        errored = workflow.events.and(status: :error).exists?
        if errored
          workflow_status = :error
        else
          executing = workflow.events.and(status: :executing).exists?
          workflow_status = :executing if executing
        end
        workflow_status
      end
    end

    resource 'workflows' do
      desc "Creates a new workflow. If the workflow with the given parameter already exists, returns the existing workflow.", {
        action_descriptor: action_description(:create) do |create|
          create.parameters do |parameters|
            fields = WorkflowServer::Models::Workflow.fields
            parameters.string :workflow_type, description: fields["workflow_type"].label, required: true, location: 'body'
            parameters.object :subject, description: fields["subject"].label, required: true, location: 'body' do
            end
            parameters.string :decider, description: fields["decider"].label, required: true, location: 'body'
            parameters.string :name, description: "Name of the workflow", required: true, location: 'body'
          end
          create.response do |workflow|
            ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Workflow, workflow)
          end
        end
      }
      post "/" do
        params[:user] = current_user
        wf = WorkflowServer.find_or_create_workflow(params)
        if wf.valid?
          wf
        else
          raise WorkflowServer::InvalidParameters, wf.errors.to_hash
        end
      end

      desc "Use this endpoint to backfill existing workflows to backbeat. Schedule timers for things that are supposed to go off in future.", {
        action_descriptor: action_description(:backfill_timer) do |backfill|
          backfill.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            parameters.string :name, description: 'the name for the timer', required: true, location: 'url'
            parameters.string :run_at, description: 'The time when this timer should go off. If in past, the timer will fire immediately.', required: true, location: 'body'
          end
        end
      }
      params do
        requires :run_at, type: String, desc: 'Timers need a run_at parameter'
      end
      put "/:id/backfill/timer/:name" do
        workflow = find_workflow(params[:id])
        WorkflowServer::Models::Timer.create!(name: params[:name], workflow: workflow, fires_at: params[:run_at], user: current_user).start
        { success: true }
      end

      desc "Use this endpoint to backfill existing workflows to backbeat. Add historical decisions that were completed successfully in the past", {
        action_descriptor: action_description(:backfill_decision) do |backfill|
          backfill.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            parameters.string :name, description: 'the name for the decision', required: true, location: 'url'
          end
        end
      }
      put "/:id/backfill/decision/:name" do
        workflow = find_workflow(params[:id])
        signal = WorkflowServer::Models::Signal.create!(name: params[:name], workflow: workflow, status: :complete, user: current_user)
        decision = WorkflowServer::Models::Decision.create!(name: params[:name], workflow: workflow, status: :complete, parent: signal, user: current_user)
        { success: true }
      end

      desc "Get workflows filtered by workflow_type, decider, subject and the workflow name.", {
        action_descriptor: action_description(:get_workflows) do |get_workflows|
          get_workflows.parameters do |parameters|
            fields = WorkflowServer::Models::Workflow.fields
            parameters.string :workflow_type, description: fields["workflow_type"].label, required: false, location: 'body'
            parameters.object :subject, description: fields["subject"].label, required: false, location: 'body' do
            end
            parameters.string :decider, description: fields["decider"].label, required: false, location: 'body'
            parameters.string :name, description: "Name for the workflow", required: false, location: 'body'
          end
          get_workflows.response do |response|
            response.array(:workflows) do |workflows|
              workflows.object do |workflow|
                ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      put "/" do
        query = {}
        [:workflow_type, :decider, :subject].each do |query_param|
          if params.include?(query_param)
            query[query_param] = params[query_param]
          end
        end
        current_user.workflows.where(query).map {|wf| wf }
      end

      desc "Get workflow identified by the id.", {
        action_descriptor: action_description(:get_workflow) do |get_workflow|
          get_workflow.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          get_workflow.response do |workflow|
            ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Workflow, workflow)
          end
        end
      }
      get "/:id" do
        find_workflow(params[:id])
      end

      {
        flags: WorkflowServer::Models::Flag,
        signals: WorkflowServer::Models::Signal,
        decisions: WorkflowServer::Models::Decision,
        activities: WorkflowServer::Models::Activity,
        timers: WorkflowServer::Models::Timer,
        events: WorkflowServer::Models::Event
      }.each_pair do |event_type, model|
        desc "Get all the #{event_type} on a workflow.", {
          action_descriptor: action_description(("get_" + event_type.to_s).to_sym) do |event|
            event.parameters do |parameters|
              parameters.string :id, description: 'the workflow id', required: true, location: 'url'
              parameters.string :status, description: 'status of the event', required: false, location: 'query'
            end
            event.response do |response|
              response.array(event_type) do |event_object|
                event_object.object do |object|
                  ServiceDiscoveryResponseCreator.call(model, object)
                end
              end
            end
          end
        }
        get "/:id/#{event_type}" do
          wf = find_workflow(params[:id])
          if params[:status].blank?
            wf.__send__(event_type)
          else
            wf.__send__(event_type).and(:status.in => Array(params[:status]))
          end
        end
      end

      desc "Get the workflow tree as a hash.", {
        # TODO - figure out how this can be made more generic
        action_descriptor: action_description(:get_workflow_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
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
        wf = find_workflow(params[:id])
        wf.tree
      end

      desc "Get the workflow status.", {
        action_descriptor: action_description(:get_workflow_status) do |get_workflow_status|
          get_workflow_status.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          get_workflow_status.response do |response|
            response.string :status, description: "the workflow status"
          end
        end
      }
      get "/:id/status" do
        status = workflow_status(find_workflow(params[:id]))
        {status: status}
      end

      desc "Get the workflow tree in a pretty print color encoded string format.", {
        action_descriptor: action_description(:print_workflow_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          tree.response do |response|
            response.string :print, description: "the workflow tree in a color coded string format."
          end
        end
      }
      get "/:id/tree/print" do
        begin
          identity_map_enabled = Mongoid.identity_map_enabled
          Mongoid.identity_map_enabled = true
          wf = find_workflow(params[:id])
          # load the child relation for each event into memory
          WorkflowServer::Models::Event.where(workflow_id: wf.id).includes(:children).flatten;1
          {print: wf.tree_to_s}
        ensure
          Mongoid.identity_map_enabled = identity_map_enabled
        end
      end


      desc "Send a signal to the workflow.", {
        action_descriptor: action_description(:signal_workflow) do |signal|
          fields = WorkflowServer::Models::Signal.fields
          signal.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            parameters.string :name, description: 'the signal name', required: true, location: 'url'
            parameters.object :options, description: 'the options for the signal', required: false, location: 'body' do |options|
              options.object :client_data, description: fields['client_data'].label, required: false, location: 'body' do
              end
              options.object :client_metadata, description: fields['client_metadata'].label, required: false, location: 'body' do
              end
            end
          end
          signal.response do |response|
            ServiceDiscoveryResponseCreator.call(WorkflowServer::Models::Signal, response)
          end
        end
      }
      params do
        optional :options, type: Hash
      end
      post "/:id/signal/:name" do
        wf = find_workflow(params[:id])
        options = params[:options] || {}
        client_data = options[:client_data] || {}
        client_metadata = options[:client_metadata] || {}
        if Migration.migrate?(wf.workflow_type)
          Migration::Workers::SignalDelegate.perform_async(wf.id, params, client_data, client_metadata)
          { action_completed: "Delgating Signal to V1 or V2" }
        else
          wf.signal(params[:name], client_data: client_data, client_metadata: client_metadata)
        end
      end

      desc "Pause an open workflow.", {
        action_descriptor: action_description(:pause_workflow) do |pause|
          pause.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
        end
      }
      put "/:id/pause" do
        wf = find_workflow(params[:id])
        wf.pause
        {success: true}
      end

      desc "Resume a paused workflow.", {
        action_descriptor: action_description(:resume_workflow) do |resume|
          resume.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
        end
      }
      put "/:id/resume" do
        wf = find_workflow(params[:id])
        wf.resume
        {success: true}
      end
    end
  end
end

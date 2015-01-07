require "grape"
require "service-discovery"
require "workflow_server/logger"
require "api/api_helpers"

module Api
  class Debug < Grape::API
    include WorkflowServer::Logger
    extend ServiceDiscovery::Description::Dsl

    helpers ApiHelpers

    namespace 'debug' do
      desc 'returns workflows that have something in error or timeout state', {
        action_descriptor: action_description(:get_error_workflows, deprecated: true) do |error_workflows|
          error_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          error_workflows.response do |response|
            response.array(:error_workflows) do |error_workflow|
              error_workflow.object do |workflow|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/error_workflows' do
        workflow_ids = WorkflowServer::Models::Event.where(:status.in => [:error, :timeout], user: current_user).pluck(:workflow_id).uniq
        WorkflowServer::Models::Workflow.where(:_id.in => workflow_ids, :status.ne => :pause)
      end

      desc 'returns paused workflows', {
        action_descriptor: action_description(:get_paused_workflows, deprecated: true) do |paused_workflows|
          paused_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          paused_workflows.response do |response|
            response.array(:paused_workflows) do |paused_workflow|
              paused_workflow.object do |workflow|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/paused_workflows' do
        current_user.workflows.where(status: :pause)
      end

      desc 'returns workflows that have > 0 open decisions and 0 executing decisions', {
        action_descriptor: action_description(:get_stuck_workflows, deprecated: true) do |stuck_workflows|
          stuck_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          stuck_workflows.response do |response|
            response.array(:paused_workflows) do |stuck_workflow|
              stuck_workflow.object do |workflow|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/stuck_workflows' do
        WorkflowServer::Models::Decision.where(status: :open, user: current_user).find_all {|decision| decision.workflow.decisions.where(:status.in => [:error, :executing, :restarting, :sent_to_client]).none? }.map(&:workflow).uniq.find_all {|wf| !wf.paused?}
      end

      desc 'returns workflows with events executing for over 24 hours', {
        action_descriptor: action_description(:long_running_events, deprecated: true) do |long_running_events|
          long_running_events.response do |response|
            response.array(:long_running_events) do |stuck_workflow|
              stuck_workflow.object do |workflow|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/long_running_events' do
        long_running_events = WorkflowServer::Models::Event.where(:status.in => [:executing, :restarting, :sent_to_client, :retrying], user: current_user).and(:_type.nin => [WorkflowServer::Models::Workflow]).and(:updated_at.lt => 24.hours.ago)
        long_running_events.map(&:workflow).find_all {|wf| !wf.paused? && wf.status != :complete && wf.events.where(status: :error).empty? }.uniq
      end

      desc 'returns workflows that have more than one decision executing simultaneously', {
        action_descriptor: action_description(:get_workflows_with_multiple_executing_decisions, deprecated: true) do |workflows_with_multiple_executing_decisions|
          workflows_with_multiple_executing_decisions.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          workflows_with_multiple_executing_decisions.response do |response|
            response.array(:workflow) do |workflow_with_multiple_executing_decision|
              workflow_with_multiple_executing_decision.object do |workflow|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/multiple_executing_decisions' do
        workflow_ids = group_by_and_having(WorkflowServer::Models::Event.where(:status.nin => [:open, :complete, :resolved, :error], user: current_user ).type(WorkflowServer::Models::Decision).selector, 'workflow_id', 1)
        current_user.workflows.where(:id.in => workflow_ids)
      end

      desc 'returns workflows that are in an inconsistent state', {
        action_descriptor: action_description(:get_inconsistent_workflows, deprecated: true) do |inconsistent_workflows|
          inconsistent_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          inconsistent_workflows.response do |response|
            response.array(:inconsistent_workflow) do |inconsistent_workflow|
              inconsistent_workflow.object do |workflow|
                ApiHelpers::SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/inconsistent_workflows' do
        parents_with_multiple_decisions = group_by_and_having(WorkflowServer::Models::Event.where(_type: WorkflowServer::Models::Decision).selector, 'parent_id', 1)
        inconsistent_workflow_ids = WorkflowServer::Models::Event.where(user: current_user, :_id.in => parents_with_multiple_decisions, :_type.in => [ WorkflowServer::Models::Timer, WorkflowServer::Models::Signal ]).pluck(:workflow_id).uniq
        WorkflowServer::Models::Workflow.where(:id.in => inconsistent_workflow_ids)
      end
    end
  end
end

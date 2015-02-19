require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'

module Migration
  module Workers
    class SignalDelegate
      include Sidekiq::Worker

      sidekiq_options retry: 4,
                      backtrace:  true,
                      queue: WorkflowServer::Config.options[:signal_delegate_queue]

      def perform(v1_workflow_id, v1_user_id, params, client_data, client_metadata)
        v1_workflow = WorkflowServer::Models::Workflow.find(v1_workflow_id)
        v2_user = V2::User.find_by_uuid(v1_user_id)
        v2_workflow = MigrateWorkflow.find_or_create_v2_workflow(v1_workflow, v2_user.id)

        v2_workflow.with_lock do
          if v2_workflow.migrated?
            params = params.with_indifferent_access
            params[:options][:metadata] = params[:options][:client_metadata].merge({ "version"=> "v2" })
            V2::Server.signal(v2_workflow, params.with_indifferent_access)
          else
            v1_workflow.signal(params["name"], client_data: client_data, client_metadata: client_metadata)
          end
        end
      end
    end
  end
end

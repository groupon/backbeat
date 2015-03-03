require 'sidekiq'
require 'sidekiq-failures'
require 'workflow_server/config'
require 'migration/migrate_workflow'

module Migration
  module Workers
    class SignalDelegate
      include Sidekiq::Worker

      sidekiq_options retry: 4,
                      backtrace:  true,
                      queue: WorkflowServer::Config.options[:signal_delegate_queue]

      def perform(v1_workflow_id, params, client_data, client_metadata)
        log_data = {
          v1_workflow_id: v1_workflow_id,
          params: params,
          client_data: client_data,
          client_metadata: client_metadata
        }

        Instrument.instrument(self.class.to_s + "_perform", log_data) do
          v1_workflow = WorkflowServer::Models::Workflow.find(v1_workflow_id)
          v2_workflow = MigrateWorkflow.find_or_create_v2_workflow(v1_workflow)

          schedule_v2 = false
          v2_workflow.with_lock do
            if v2_workflow.migrated?
              params = params.with_indifferent_access
              params[:options][:metadata] = client_metadata.merge({ "version"=> "v2" })
              V2::Server.signal(v2_workflow, params.with_indifferent_access)
              Instrument.log_msg(self.class.to_s + "_v2_signal_sent", log_data)
              schedule_v2 = true
            else
              v1_workflow.signal(params["name"], client_data: client_data, client_metadata: client_metadata)
              Instrument.log_msg(self.class.to_s + "_v1_signal_sent", log_data)
            end
          end
          # We have to call this outside lock other wise this asynchronous task will not have the new signal on it
          # since with_lock does not prevent reads from occuring
          V2::Server.fire_event(V2::Events::ScheduleNextNode, v2_workflow) if schedule_v2
        end
      end
    end
  end
end

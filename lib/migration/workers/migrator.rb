require 'sidekiq'
require 'workflow_server/config'
require 'migration/migrate_workflow'

module Migration
  module Workers
    class Migrator
      include Sidekiq::Worker

      sidekiq_options retry: false,
                      backtrace:  true,
                      queue: WorkflowServer::Config.options[:migrator_queue]

      def perform(v1_workflow_id, options = {})
        Instrument.instrument(self.class.to_s + "_perform", { v1_workflow_id: v1_workflow_id }) do
          v1_workflow = WorkflowServer::Models::Workflow.find(v1_workflow_id)
          v2_workflow = MigrateWorkflow.find_or_create_v2_workflow(v1_workflow)
          options = options.reduce({}) { |m, (k, v)| m[k.to_sym] = v; m }

          MigrateWorkflow.call(v1_workflow, v2_workflow, options)
        end
      end
    end
  end
end

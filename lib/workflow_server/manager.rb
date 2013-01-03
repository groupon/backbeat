module WorkflowServer
  class Manager
    class << self

      def schedule_next_decision(workflow)
        workflow.with_lock do
          unless Models::Decision.where(workflow: workflow, status: :executing).exists?
            if (next_decision = Models::Decision.where(workflow: workflow, status: :open).first)
              next_decision.start
            end
          end
        end
      end

      def get_event(id)
        Models::Event.find(id)
      end

      def find_or_create_workflow(workflow_type, subject_type, subject_id, decider = nil)
        Models::Workflow.find_or_create_by(workflow_type: workflow_type, subject_type: subject_type, subject_id: subject_id, decider: decider)
      end
    end
  end
end

module WorkflowServer
  module Models
    class ContinueAsNewWorkflowFlag < Flag

      def start
        all_past_events = workflow.events.where(:sequence.lt => self.sequence)
        all_past_events.update_all(status: :complete, inactive: true)
        all_past_events.map(&:destroy_jobs)
        super
        completed
      end

    end
  end
end
module WorkflowServer
  module Models
    class WorkflowCompleteFlag < Flag

      def start
        workflow.completed
        super
      end

    end
  end
end

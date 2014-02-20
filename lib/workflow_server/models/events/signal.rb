module WorkflowServer
  module Models
    class Signal < Event

      def start
        super
        add_decision(name)
        completed
      end

      def child_completed(child_id)
        WorkflowServer.schedule_next_decision(workflow)
      end

    end
  end
end

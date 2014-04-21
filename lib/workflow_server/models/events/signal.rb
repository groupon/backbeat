module WorkflowServer
  module Models
    class Signal < Event

      def start
        super
        add_decision(name)
        completed
      end

      def add_decision(decision_name, orphan = false)
        if children.any?
          raise 'You cannot add a decision to a Signal that already has one!'
        end
        super
      end

      def child_completed(child_id)
        WorkflowServer.schedule_next_decision(workflow)
      end

    end
  end
end

module WorkflowServer
  module Models
    class Branch < Activity
      # A branchs is exactly the same as an activity but provides a distinction between
      # activities that do work and activities that only determine the next decision.


      def add_decision(decision_name, orphan = false)
        if children.any?
          raise 'You cannot add a decision to a Branch that already has one!'
        end
        super
      end

      def validate_next_decision(next_decision_arg)
        unless next_decision_arg
          raise WorkflowServer::InvalidDecisionSelection.new("branch:#{name} has to make a decision or return none.")
        end
        super
      end

    end
  end
end

module WorkflowServer
  module Models
    class Branch < Activity
      # A branchs is exactly the same as an activity but provides a distinction between
      # activities that do work and activities that only determine the next decision.

      def validate_next_decision(next_decision_arg)
        unless next_decision_arg
          raise WorkflowServer::InvalidDecisionSelection.new("branch:#{name} has to make a decision or return none.")
        end
        super
      end

    end
  end
end

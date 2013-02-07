module WorkflowServer
  module Models
    class Signal < Event

      after_create :start

      def start
        super
        add_decision(name)
        completed
      end

      def depth
        1
      end

    end
  end
end

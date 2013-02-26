module WorkflowServer
  module Models
    class Signal < Event

      def start
        super
        add_decision(name)
        completed
      end

    end
  end
end

module WorkflowServer
  module Models
    class Signal < Event

      after_create :start

      def start
        super
        add_decision(name)
        update_status!(:complete)
      end

      def completed
        update_status!(:complete)
        super
      end
    end
  end
end

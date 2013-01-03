module WorkflowServer
  module Models
    class Flag < Event

      def start
        super
        completed
      end

      def completed
        update_status!(:complete)
        super
      end
    end
  end
end

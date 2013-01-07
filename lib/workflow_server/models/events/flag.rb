module WorkflowServer
  module Models
    class Flag < Event

      def start
        super
        completed
      end
    end
  end
end

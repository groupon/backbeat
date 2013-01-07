module WorkflowServer
  module Models
    class Timer < Event
      field :fires_at, type: Time

      validates_presence_of :fires_at

      def start
        super
        update_status!(:executing)
        Delayed::Backend::Mongoid::Job.enqueue(self, run_at: fires_at)
      end

      def fire
        add_decision(name)
        completed
      end
      alias_method :perform, :fire

      def print_name
        super + " - fires_at: #{fires_at}"
      end
    end
  end
end

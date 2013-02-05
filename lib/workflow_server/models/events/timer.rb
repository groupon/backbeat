module WorkflowServer
  module Models
    class Timer < Event
      field :fires_at, type: Time

      validates_presence_of :fires_at

      def start
        super
        update_status!(:executing)
        WorkflowServer::Async::Job.schedule({event: self, method: :fire, max_attempts: 5}, fires_at)
      end

      def fire
        add_decision(name)
        completed
      end

    end
  end
end

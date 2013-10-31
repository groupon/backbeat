module WorkflowServer
  module Models
    class Timer < Event
      field :fires_at, type: Time

      validates_presence_of :fires_at

      index({ fires_at: 1 })

      field :mode, type: Symbol, default: :fire_and_forget

      def start
        super
        update_status!(:scheduled)
        enqueue_fire(max_attempts: 5, fires_at: fires_at)
      end

      def fire
        return if status == :complete
        mode == :blocking ? add_interrupt(name) : add_decision(name)
        completed
      end

    end
  end
end
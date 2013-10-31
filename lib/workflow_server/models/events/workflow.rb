module WorkflowServer
  module Models
    class Workflow < Event

      field :workflow_type, type: Symbol, label: "The type of workflow e.g. approval_workflow, payment_workflow"
      field :subject, type: Hash, label: "Subject is the entity on which this workflow is defined. It can be a model, date or a combination of things that uniquely define the workflow entity"
      field :decider, type: String, label: "The entity on the client side that will handle decision tasks for this workflow"
      field :mode, type: Symbol, default: :blocking
      field :start_signal, type: Symbol
      field :_event_sequence, type: Integer, default: 0

      has_many :events, inverse_of: :workflow, order: {sequence: 1}, dependent: :destroy

      validates_presence_of :workflow_type, :subject, :decider

      index({ workflow_type: 1, subject: 1 }, { unique: true, sparse: true })
      index({ subject: 1 }, { sparse: true })

      def serializable_hash(options = {})
        hash = super
        Marshal.load(Marshal.dump(hash))
      end

      def signal(name, options = {})
        raise WorkflowServer::EventComplete, "Workflow with id(#{id}) is already complete" if status == :complete
        signal = WorkflowServer::Models::Signal.create!({name: name, workflow: self, user: user}.merge(options))
        signal.enqueue_start
        signal
      end

      def blocking?
        mode == :blocking
      end

      def completed
        if workflow
          next_decision = "#{name}_succeeded".to_sym
          # Let the parent know you are done
          workflow.signal(next_decision)
        end
        super
      end

      def errored(error)
        if workflow
          next_decision = "#{name}_errored".to_sym
          # Let the parent know you errored. Think more about it.
          workflow.signal(next_decision)
        end
        super
      end

      def start
        super
        if start_signal
          # send the start signal on the workflow
          self.signal(start_signal)
        end
        update_status!(:executing)
      end

      def pause
        raise WorkflowServer::InvalidEventStatus, "A workflow cannot be paused while in #{status} state" unless [:open, :pause, :executing].include?(status)
        paused
      end

      def paused?
        status == :pause
      end

      def resume
        raise WorkflowServer::InvalidEventStatus, "A workflow cannot be resumed unless it is paused" unless status == :pause
        resumed
      end

      def resumed
        with_lock do
          update_status!(:open)
        end
        debug("Total paused events #{paused_events.count}")
        paused_events.map(&:resumed)
        super
      end

      def paused_events
        events.where(status: :pause)
      end

      def next_sequence
        if topmost_workflow == self
          # if I am the top level workflow, start with 0
          return 0
        end
        super
      end

      alias_method :my_user, :user

      {
        flags: Flag,
        decisions: Decision,
        signals: Signal,
        timers: Timer,
        activities: [Activity, SubActivity, Branch],
      }.each_pair do |name, klass|
          #
          # Returns events of the given type
          #
          define_method(name) do
            arel = events.any_in(_type: Array(klass))
            if block_given?
              arel.each do |record|
                yield record
              end
            else
              arel.all
            end
          end

          #
          # Returns events of a particular type in the past given the reference task
          #
          define_method("past_#{name}") do |task|
            arel = events.where(:sequence.lt => task.sequence).type(klass.to_s)
            if block_given?
              arel.each do |record|
                yield record
              end
            else
              arel.all
            end
          end
        end

        def get_children
          self.events.where(parent: nil)
        end

        def show
          events.each do |e|
            ap e.attributes
          end
        end

    end
  end
end

module WorkflowServer
  module Models
    class Workflow < Event

      field :workflow_type, type: Symbol
      field :subject_id, type: Integer
      field :subject_klass, type: String
      field :decider, type: String
      field :mode, type: Symbol, default: :blocking
      field :error_workflow, type: Boolean, default: false # whether this workflow should retry the parent decision on complete
      field :start_signal, type: Symbol

      has_many :events, inverse_of: :workflow, order: {sequence: 1}, dependent: :destroy

      belongs_to :user, index: true

      validates_presence_of :workflow_type, :subject_id, :subject_klass, :decider, :user

      index({ workflow_type: 1, subject_klass: 1, subject_id: 1 }, { unique: true, sparse: true })
      index({ subject_klass: 1, subject_id: 1 }, { sparse: true })
      index({ workflow_type: 1 }, { sparse: true })

      def signal(name)
        raise WorkflowServer::EventComplete, "Workflow with id(#{id}) is already complete" if status == :complete
        WorkflowServer::Models::Signal.create!(name: name, workflow: self)
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

      def depth
        parent.nil? ? 0 : super
      end

      def start
        super
        update_status!(:executing)
        if start_signal
          # send the start signal on the workflow
          self.signal(start_signal)
        end
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
            arel = events.type(klass)
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

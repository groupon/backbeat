module WorkflowServer
  module Models
    class Workflow < Event

      field :workflow_type, type: Symbol
      field :subject_id, type: Integer
      field :subject_type, type: String
      field :decider, type: String
      field :mode, type: Symbol, default: :blocking
      field :error_workflow, type: Boolean, default: false # whether this workflow should retry the parent decision on complete
      field :start_signal, type: Symbol

      index({ workflow_type: 1, subject_type: 1, subject_id: 1 }, { unique: true })

      has_many :events, inverse_of: :workflow, order: {created_at: 1}

      belongs_to :user

      validates_presence_of :workflow_type, :subject_id, :subject_type, :decider, :user

      def signal(name)
        raise WorkflowServer::EventComplete, "Workflow with id(#{id}) is already complete" if status == :complete
        WorkflowServer::Models::Signal.create!(name: name, workflow: self)
      end

      def blocking?
        mode == :blocking
      end

      def completed
        if parent
          next_decision ||= "#{name}_succeeded".to_sym
          # Let the parent know you are done
          parent.add_decision(next_decision)
        end
        super
      end

      def errored(error)
        if parent
          next_decision ||= "#{name}_errored".to_sym
          # Let the parent know you errored. Think more about it.
          parent.add_decision(next_decision)
        end
        super
      end

      def start
        super
        update_status!(:executing)
        if start_signal
          # send the start signal on the workflow
          self.signal(start_signal)
        end
      end

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
          arel = events.where(:created_at.lte => task.created_at, :id.ne => task.id).type(klass.to_s)
          if block_given?
            arel.each do |record|
              yield record
            end
          else
            arel.all
          end
        end
      end

      def print_tree
        data = {}
        data['root_node'] = Tree::TreeNode.new(workflow_type.to_s + " " + subject_id.to_s)
        self.events.each do |event|
          node = Tree::TreeNode.new(event.print_name, event.id)
          data[event.parent.try(:id) || 'root_node'] << node
          data[event.id] = node
        end
        data['root_node'].print_tree
      end
    end
  end
end
module WorkflowServer
  module Models
    class Activity < Event

      field :mode, type: Symbol, default: :blocking
      field :always, type: Boolean, default: false
      field :retry, type: Integer, default: 3
      field :retry_interval, type: Integer, default: 15.minutes
      field :time_out, type: Integer, default: 0
      field :method, type: Boolean, default: false
      field :valid_next_decisions, type: Array, default: []

      # These fields come from client
      field :arguments
      field :result
      field :next_decision, type: String

      validate :not_blocking_and_always

      index({ mode: 1 }, { sparse: true })

      def not_blocking_and_always
        if mode == :blocking && always
          errors.add(:base, "#{self.class} cannot be blocking and always")
        end
      end

      def start
        super
        update_status!(:executing)
        WorkflowServer::Async::Job.schedule(event: self, method: :send_to_client, max_attempts: 25)
      end
      alias_method :continue, :start

      def completed
        with_lock do
          unless subactivities_running?
            really_complete
            super
          else
            Watchdog.feed(self) if time_out > 0
            update_status!(:waiting_for_sub_activities)
          end
        end
      end

      def run_sub_activity(options = {})
        raise WorkflowServer::InvalidEventStatus, "Cannot run subactivity while in status(#{status})" unless status == :executing
        unless options[:always]
          return if subactivity_handled?(options[:name], options[:arguments])
        end

        sub_activity = create_sub_activity!(options)
        reload
        Watchdog.feed(self) if time_out > 0

        sub_activity.start
        update_status!(:running_sub_activity) if sub_activity.blocking?
        sub_activity
      end

      def child_completed(child)
        super
        if child.is_a?(SubActivity)
          if child.blocking?
            continue
          else
            with_lock do
              completed if status == :waiting_for_sub_activities
            end
          end
        end
      end

      def blocking?
        mode == :blocking
      end

      def method?
        method
      end

      def fire_and_forget?
        mode == :fire_and_forget
      end

      def change_status(new_status, args = {})
        return if status == new_status.to_sym
        case new_status.to_sym
        when :completed
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}" unless [:executing, :timeout].include?(status)
          update_attributes!(result: args[:result], next_decision: verify_and_get_next_decision(args[:next_decision]))
          completed
        when :errored
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}" unless [:executing, :timeout].include?(status)
          errored(args[:error])
        else
          raise WorkflowServer::InvalidEventStatus, "Invalid status #{new_status}"
        end
      end

      def errored(error)
        Watchdog.kill(self) if time_out > 0
        if retry?
          do_retry(error)
        else
          super
          # Add a decision task if this is a top level activity
          add_decision("#{name}_errored".to_sym) if parent.is_a?(Decision)
        end
      end

      def verify_and_get_next_decision(next_decision_arg)
        validate_next_decision(next_decision_arg)
        next_decision_arg || "#{name}_succeeded"
      end

      def validate_next_decision(next_decision_arg)
        if next_decision_arg && next_decision_arg.to_s != 'none'
          unless valid_next_decisions.map(&:to_s).include?(next_decision_arg.to_s)
            raise WorkflowServer::InvalidDecisionSelection.new("activity:#{name} tried to make #{next_decision_arg} the next decision but is not allowed to.")
          end
        end
      end

      private

      def retry?
        status_history.find_all {|s| s[:to] == :retrying || s['to'] == :retrying }.count < self.retry
      end

      def do_retry(error)
        update_status!(:failed, error)
        notify_of(:error_retry, error: error)
        unless retry_interval > 0
          start
        else
          WorkflowServer::Async::Job.schedule({event: self, method: :start, max_attempts: 5}, retry_interval.from_now)
        end
        update_status!(:retrying)
      end

      def really_complete
        Watchdog.kill(self) if time_out > 0
        if parent.is_a?(Decision) && next_decision != 'none'
          #only top level activities are allowed schedule a next decision
          add_decision(next_decision) if next_decision
        end
      end

      def create_sub_activity!(options = {})
        sa_name = options.delete(:name)
        sub_activity = SubActivity.new({name: sa_name, parent: self, workflow: workflow}.merge(options))
        sub_activity.valid? ? sub_activity.save! : raise(WorkflowServer::InvalidParameters, {sub_activity.event_type => sub_activity.errors})
        sub_activity
      end

      def subactivities_running?
        children.where(:mode.ne => :fire_and_forget, :status.ne => :complete).type(SubActivity).any?
      end

      def subactivity_handled?(name, arguments)
        children.type(SubActivity).where(name: name, arguments: arguments).any?
      end

      def send_to_client
        WorkflowServer::Client.perform_activity(self)
        Watchdog.start(self, :timeout, time_out) if time_out > 0
      end
    end
  end
end
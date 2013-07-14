module WorkflowServer
  module Models
    class Activity < Event

      field :mode, type: Symbol, default: :blocking, label: "Defines the concurrency level. Valid values are blocking, non_blocking and fire_and_forget. 1) blocking implies this activity will execute in isolation 2) non_blocking implies other activities can execute while this one is running. The parent of this activity will wait for this activity to complete before calling complete on itself 3) fire_and_forget is similar to non_blocking except the parent won't wait for this activity to complete. DEFAULT is blocking"
      field :always, type: Boolean, default: false
      field :retry, type: Integer, default: 6, label: "The number of times this activity will be retried on error. Default is 6."
      field :retry_interval, type: Integer, default: 20.minutes, label: "The retry interval. Default is 20 minutes"
      field :time_out, type: Integer, default: 0, label: "There is no default timeout"
      field :valid_next_decisions, type: Array, default: [], label: "The range of valid next decision. next_decision can be null, none or one of the values from valid_next_decisions"
      field :orphan_decision, type: Boolean, default: false, label: "true implies next_decision will be a top-level decision and not a child of this activity. This field is ignored when next_decision is null. Default is false"

      # indicates whether the client has called completed endpoint on this activity
      field :_client_done_with_activity, type: Boolean, default: false

      # These fields come from client
      field :result, label: "Use this field to store the result of an activity"
      field :next_decision, type: String, label: "Use this field to schedule the next decision when this activity completes"

      validate :not_blocking_and_always

      def not_blocking_and_always
        if mode == :blocking && always
          errors.add(:base, "#{self.class} cannot be blocking and always")
        end
      end

      def start
        super
        enqueue_send_to_client(max_attempts: 25)
        update_status!(:executing)
      end
      alias_method :continue, :start

      def restart
        raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to restarting" unless [:error, :timeout].include?(status)
        update_status!(:restarting)
        start
      end

      def completed
        if next_decision && next_decision != 'none'
          #only top level activities are allowed to schedule the next decision
          make_decision(next_decision)
        end
        super
      end

      def make_decision(decision_name, orphan = false)
        if orphan_decision
          add_decision(decision_name, true)
        else
          add_interrupt(decision_name, orphan)
        end
      end

      def complete_if_done
        Watchdog.feed(self) if time_out > 0
        if self._client_done_with_activity && status != :complete && !children_running?
          with_lock do
            completed if status != :complete
          end
        end
      end

      def run_sub_activity(options = {})
        raise WorkflowServer::InvalidEventStatus, "Cannot run subactivity while in status(#{status})" unless status == :executing
        unless options[:always]
          return if subactivity_handled?(options[:name], options[:client_data] || {})
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

        if child.is_a?(Activity)
          if child.blocking?
            continue
          elsif child.mode != :fire_and_forget
            complete_if_done
          end
        else
          complete_if_done
        end
      end

      def blocking?
        mode == :blocking
      end

      def fire_and_forget?
        mode == :fire_and_forget
      end


      ALLOWED_TRANSITIONS_TO_FROM = { completed: { executing: true, timeout: true },
                                      errored:   { executing: true, timeout: true } }

      def change_status(new_status, args = {})
        new_status = new_status.to_sym

        return if status == new_status.to_sym

        unless ALLOWED_TRANSITIONS_TO_FROM[new_status].try(:[], status)
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}"
        end

        case new_status.to_sym
        when :completed
          update_attributes!(result: args[:result], next_decision: verify_and_get_next_decision(args[:next_decision]), _client_done_with_activity: true)
          Watchdog.feed(self) if time_out > 0
          enqueue_complete_if_done
        when :errored
          errored(args[:error])
        end
      end

      def errored(error)
        Watchdog.dismiss(self) if time_out > 0
        if retry?
          do_retry(error)
        else
          super
          handle_error(error)
        end
      end

      def verify_and_get_next_decision(next_decision_arg)
        validate_next_decision(next_decision_arg)
        next_decision_arg
      end

      def validate_next_decision(next_decision_arg)
        if next_decision_arg && next_decision_arg.to_s != 'none'
          unless valid_next_decisions.include?('any') ||  valid_next_decisions.include?(next_decision_arg.to_s)
            raise WorkflowServer::InvalidDecisionSelection.new("Activity:#{name} tried to make #{next_decision_arg} the next decision but is not allowed to.")
          end
        end
      end

      def resumed
        send_to_client
        super
      end

      def child_resumed(child)
        unless child.respond_to?(:fire_and_forget?) && child.fire_and_forget?
          Watchdog.start(self, :timeout, time_out) if time_out > 0
        end
        super
      end

      private

      def retry?
        status_history.find_all {|s| s[:to] == :retrying || s['to'] == :retrying }.count < self.retry
      end

      def do_retry(error)
        update_status!(:failed, error)
        if retry_interval > 0
          enqueue_start(max_attempts: 5, fires_at: retry_interval.from_now)
        else
          start
        end
        update_status!(:retrying)
      end

      def create_sub_activity!(options = {})
        sa_name = options.delete(:name)
        sub_activity = SubActivity.new({name: sa_name, parent: self, workflow: workflow, user: user}.merge(options))
        sub_activity.valid? ? sub_activity.save! : raise(WorkflowServer::InvalidParameters, {sub_activity.event_type => sub_activity.errors})
        sub_activity
      end

      def children_running?
        children.where(:mode.ne => :fire_and_forget, :status.ne => :complete).any?
      end

      def subactivity_handled?(name, client_data)
        children.type(SubActivity).where(name: name, client_data: client_data).any?
      end

      def send_to_client
        if workflow.paused?
          workflow.with_lock do
            if workflow.paused?
              paused
              return
            end
          end
        end
        WorkflowServer::Client.perform_activity(self)
        update_status!(:executing)
        Watchdog.start(self, :timeout, time_out) if time_out > 0
      end

      def handle_error(error)
        return if mode == :fire_and_forget
        add_interrupt("#{parent_decision.name}_error") if parent_decision
      end

    end
  end
end

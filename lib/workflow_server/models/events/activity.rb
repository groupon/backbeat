module WorkflowServer
  module Models
    class Activity < Event

      field :mode, type: Symbol, default: :blocking
      field :always, type: Boolean, default: false
      field :retry, type: Integer, default: 3
      field :retry_interval, type: Integer, default: 15.minutes
      field :time_out, type: Integer, default: 0
      field :valid_next_decisions, type: Array, default: []
      field :orphan_decision, type: Boolean, default: false

      # indicates whether the client has called completed endpoint on this activity
      field :_client_done_with_activity, type: Boolean, default: false

      # These fields come from client
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
        enqueue_send_to_client(max_attempts: 25)
      end
      alias_method :continue, :start

      def restart
        raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to restarting" unless [:error, :timeout].include?(status)
        update_status!(:restarting)
        start
      end

      def completed
        if parent.is_a?(Decision) && next_decision && next_decision != 'none'
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

      def change_status(new_status, args = {})
        return if status == new_status.to_sym
        case new_status.to_sym
        when :completed
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}" unless [:executing, :timeout].include?(status)
          update_attributes!(result: args[:result], next_decision: verify_and_get_next_decision(args[:next_decision]), _client_done_with_activity: true)
          complete_if_done
        when :errored
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}" unless [:executing, :timeout].include?(status)
          errored(args[:error])
        else
          raise WorkflowServer::InvalidEventStatus, "Invalid status #{new_status}"
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
          unless valid_next_decisions.map(&:to_s).include?(next_decision_arg.to_s)
            raise WorkflowServer::InvalidDecisionSelection.new("Activity:#{name} tried to make #{next_decision_arg} the next decision but is not allowed to.")
          end
        end
      end

      def resumed
        send_to_client
        super
      end

      def child_resumed(child)
        Watchdog.start(self, :timeout, time_out) if time_out > 0
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
        sub_activity = SubActivity.new({name: sa_name, parent: self, workflow: workflow}.merge(options))
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
        unless workflow.paused?
          WorkflowServer::Client.perform_activity(self)
          update_status!(:executing)
          Watchdog.start(self, :timeout, time_out) if time_out > 0
        else
          workflow.with_lock do
            if workflow.paused?
              paused
            else
              send_to_client
            end
          end
        end
      end

      def handle_error(error)
        return if mode == :fire_and_forget
        add_interrupt("#{parent_decision.name}_error") if parent_decision
      end

    end
  end
end

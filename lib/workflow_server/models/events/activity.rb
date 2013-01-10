module WorkflowServer
  module Models
    class Activity < Event

      field :actor_id, type: Integer
      field :actor_type, type: String
      field :arguments, type: Array
      field :mode, type: Symbol, default: :blocking
      field :always, type: Boolean, default: false
      field :retry, type: Integer, default: 3
      field :retry_interval, type: Integer, default: 15.minutes
      field :timeout, type: Integer, default: 0
      field :method, type: Boolean, default: false

      validate :not_blocking_and_always

      def not_blocking_and_always
        if mode == :blocking && always
          errors.add(:base, 'An Activity can not be blocking and always')
        end
      end

      def start
        super
        WorkflowServer::AsyncClient.perform_activity(self)
        Watchdog.start(self, :timeout, timeout) if timeout > 0
        update_status!(:executing)
      end
      alias_method :perform, :start
      alias_method :continue, :start

      def completed
        with_lock do
          unless subactivities_running?
            Watchdog.kill(self) if timeout > 0
            super
            if parent.is_a?(Decision)
              # Add a decision task if this is a top level activity
              add_decision("#{name}_succeeded".to_sym)
            end
          else
            Watchdog.feed(self) if timeout > 0
            update_status!(:waiting_for_sub_activities)
          end
        end
      end

      def run_sub_activity(options = {})
        raise WorkflowServer::InvalidEventStatus, "Cannot run subactivity while in status(#{status})" unless status == :executing
        unless options[:always]
          return if subactivity_handled?(options[:name], options[:actor_type], options[:actor_id])
        end

        sa_name = options.delete(:name)
        sub_activity = SubActivity.new({name: sa_name, actor_id: options.delete(:actor_id), actor_type: options.delete(:actor_type), parent: self, workflow: workflow}.merge(options))
        unless sub_activity.valid?
          raise WorkflowServer::InvalidParameters, {sa_name => sub_activity.errors}
        end
        sub_activity.save!

        Watchdog.feed(self) if timeout > 0
        update_status!(:running_sub_activity)

        sub_activity.start
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

      def child_errored(child, error)
        super
        errored(error) if child.is_a?(SubActivity) && !child.fire_and_forget?
      end

      def child_timeout(child, timeout)
        super
        timeout(timeout)
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

      def retry?
        status_history.find_all {|s| s[:to] == :retrying }.count < self.retry
      end

      def retry_interval
        retry_interval
      end

      def change_status(new_status, *args)
        return if status == new_status.to_sym
        case new_status.to_sym
        when :completed
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}" if status != :executing
          completed
        when :errored
          raise WorkflowServer::InvalidEventStatus, "Activity #{self.name} can't transition from #{status} to #{new_status}" if status != :executing
          # TODO - FIX THIS
          errored(args.first)
        else
          raise WorkflowServer::InvalidEventStatus, "Invalid status #{new_status}"
        end
      end

      def errored(error)
        Watchdog.kill(self) if timeout > 0
        if retry?
          update_status!(:failed, error)
          notify_of(:error_retry, error: error)
          unless retry_interval > 0
            start
          else
            Delayed::Backend::Mongoid::Job.enqueue(self, run_at: retry_interval.from_now)
          end
          update_status!(:retrying)
        else
          super
          if parent.is_a?(Decision)
            # Add a decision task if this is a top level activity
            add_decision("#{name}_errored".to_sym)
          end
        end
      end

      def print_name
        super + " - #{actor_id}"
      end

      private

      def subactivities_running?
        children.where(:mode.ne => :fire_and_forget, :status.ne => :complete).type(SubActivity).any?
      end

      def subactivity_hash(name, actor_type, actor_id)
        {name: name, actor_type: actor_type, actor_id: actor_id}
      end

      def subactivity_handled?(name, actor_type, actor_id)
        children.where(subactivity_hash(name, actor_type, actor_id)).type(SubActivity.to_s).any?
      end

    end
  end
end
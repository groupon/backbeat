module WorkflowServer
  module Models
    class Activity < Event

      field :options, type: Hash, default: {}
      field :version, type: String
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
        WorkflowServer::AsyncClient.perform_activity(id)
        Watchdog.start(self, "#{name}_timout".to_sym, timeout) if timeout > 0
        update_status!(:executing)
      end
      alias_method :perform, :start
      alias_method :continue, :start

      def completed
        with_lock do
          unless subactivities_running?
            Watchdog.kill(self, "#{name}_timout".to_sym)
            super
            if parent.is_a?(Decision)
              # Add a decision task if this is a top level activity
              add_decision("#{name}_succeeded".to_sym)
            end
          else
            update_status!(:waiting_for_sub_activities)
          end
        end
      end

      def run_sub_activity(name, actor, *args, options)
        unless options[:always]
          return if subactivity_handled?(name, actor)
        end

        sub_activity = SubActivity.create!({name: name, actor_id: actor.id, actor_type: actor.class.to_s, arguments: args, parent: self, workflow: workflow}.merge(options))
        Watchdog.feed(self, "#{name}_timout".to_sym) if timeout > 0
        update_status!(:running_sub_activity)

        sub_activity.start

        if sub_activity.blocking?
          raise WorkflowServer::WaitForSubActivity, "Waiting for sub_activity(#{sub_activity.id}) to complete"
        end
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

      def errored(error)
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
          Watchdog.kill(self, "#{name}_timout".to_sym)
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
        children.where(:"options.mode".ne => :fire_and_forget, :status.ne => :complete).type(SubActivity).any?
      end

      def subactivity_hash(name, actor)
        {name: name, actor_id: actor.id, actor_type: actor.class.to_s}
      end

      def subactivity_handled?(name, actor)
        children.where(subactivity_hash(name, actor)).type(SubActivity.to_s).any?
      end
    end
  end
end
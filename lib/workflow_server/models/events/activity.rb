module WorkflowServer
  module Models
    class Activity < Event
      include Mongoid::Locker

      field :options, type: Hash, default: {}
      field :version, type: String
      field :actor_id, type: Integer
      field :actor_type, type: String
      field :arguments, type: Array

      DEFAULT_OPTIONS = {mode: :blocking, always: false, retry: 3, retry_interval: 15.minutes}.with_indifferent_access

      validate :not_blocking_and_always

      def not_blocking_and_always
        if execution_options[:mode] == :blocking && execution_options[:always]
          errors.add(:options, 'An Activity can not be blocking and always')
        end
      end

      def start
        super
        WorkflowServer::AsyncClient.perform_activity(id)
        update_status!(:executing)
      end
      alias_method :perform, :start
      alias_method :continue, :start

      def completed
        with_lock do
          unless subactivities_running?
            update_status!(:complete)
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

        sub_activity = SubActivity.create!(name: name, actor_id: actor.id, actor_type: actor.class.to_s, arguments: args, options: options, parent: self, workflow: workflow)
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
            completed if status == :waiting_for_sub_activities
          end
        end
      end

      def child_errored(child, error)
        super
        errored(error) if child.is_a?(SubActivity) && !child.fire_and_forget?
      end

      def blocking?
        execution_options[:mode] == :blocking
      end

      def method?
        !!execution_options[:method]
      end

      def fire_and_forget?
        execution_options[:mode] == :fire_and_forget
      end

      def execution_options
        @execution_options ||= DEFAULT_OPTIONS.merge(options)
      end

      def retry?
        execution_options[:retry] && status_history.find_all {|s| s[:to] == :retrying }.count < execution_options[:retry]
      end

      def retry_interval
        execution_options[:retry_interval] || 0
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
          update_status!(:error, error)
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

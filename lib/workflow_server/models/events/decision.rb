module WorkflowServer
  module Models
    class Decision < Event

      after_create :schedule_next_decision

      attr_accessor_with_default :decisions_to_add, []

      field :error, type: Hash

      def start
        super
        WorkflowServer::AsyncClient.make_decision(workflow.decider, self.id, workflow.subject_type, workflow.subject_id)
        Watchdog.start(self, :decision_time_out)
        update_status!(:deciding)
      end

      def add_flag(name)
        decisions_to_add << [Flag, {name: name, parent: self, workflow: workflow}]
      end

      def add_timer(name, fires_at)
        decisions_to_add << [Timer, {fires_at: fires_at, name: name, parent: self, workflow: workflow}]
      end

      def add_activity(activity_name, actor, options = {})
        decisions_to_add << [Activity, {name: activity_name, actor_id: actor.id, actor_type: actor.class.to_s, workflow: workflow, options: options, parent: self}]
      end

      def deciding
        Watchdog.feed(self, :decision_time_out)
        yield
        close
      rescue Exception => err
        errored(err)
      end

      def close
        # TODO add a timeout for this decision tree to complete
        Watchdog.kill(self, :decision_time_out)
        decisions_to_add.each do |type, args|
          type.create!(args)
        end
        update_status!(:executing)
        refresh
      end

      def refresh
        start_next_action
        completed if all_activities_completed?
      end

      def completed
        update_status!(:complete)
        Flag.create(name: "#{self.name}_completed".to_sym, workflow: workflow, parent: self, status: :complete)
        super
        schedule_next_decision
      end

      def child_completed(child)
        super
        if child.is_a?(Activity)
          refresh
        end
      end

      def child_errored(child, error)
        errored(error)
      end

      def errored(error)
        update_status!(:error)
        self.error = {error_message: error.message, backtrace: error.backtrace}
        self.save!
        super
      end

      def timeout(name)
        update_status!(:timeout)
      end

      def start_next_action
        with_lock do
          unless any_incomplete_blocking_activities?
            open_events do |event|
              event.start
              break if event.is_a?(Activity) && event.blocking?
            end
          end
        end
      end

      def open_events
        Event.where(parent: self, status: :open).each do |event|
          yield event
        end
      end

      def any_incomplete_blocking_activities?
        children.type(Activity).where(:"options.mode" => :blocking).not_in(:status => [:complete, :open]).any?
      end

      def all_activities_completed?
        !children.type(Activity).where(:"options.mode".ne => :fire_and_forget, :status.ne => :complete).any?
      end

      def schedule_next_decision
        WorkflowServer::Manager.schedule_next_decision(workflow)
      end

      # returns true if this task is a duplicate
      def duplicate?
        flag_names = past_flags.map(&:name)
        flag_names.include?("#{name}_completed".to_sym)
      end
    end

  end
end

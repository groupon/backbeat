module WorkflowServer
  module Models
    class Decision < Event

      after_create :schedule_next_decision

      attr_accessor :decisions_to_add

      def start
        super
        WorkflowServer::AsyncClient.make_decision(workflow.decider, self.id, workflow.subject_type, workflow.subject_id)
        Watchdog.start(self, :decision_deciding_time_out)
        update_status!(:deciding)
      end

      def add_flag(name)
        decisions_to_add << [Flag, {name: name, parent: self, workflow: workflow}]
      end

      def add_timer(name, time)
        fires_at = time[:at] || time[:in].from_now
        decisions_to_add << [Timer, {fires_at: fires_at, name: name, parent: self, workflow: workflow}]
      end

      def add_activity(name, actor, options = {})
        decisions_to_add << [Activity, {name: name, actor_id: actor.id, actor_type: actor.class.to_s, workflow: workflow, parent: self}.merge(options)]
      end

      def add_branch(name, branches, options = {})
        decisions_to_add << [Branch, {name: name, branches: branches, workflow: workflow, parent: self}.merge(options)]
      end

      def add_workflow(name, workflow_type, subject, decider, options = {})
        decisions_to_add << [Workflow, {name: name, workflow_type: workflow_type, subject_type: subject.class.to_s, subject_id: subject.id, decider: decider.to_s, workflow: workflow, parent: self}.merge(options)]
      end

      def complete_workflow
        decisions_to_add << [WorkflowCompleteFlag, {name: workflow.name, parent: self, workflow: workflow}]
      end

      def deciding
        Watchdog.feed(self, :decision_deciding_time_out)
        self.decisions_to_add = []
        yield
        close
      rescue Exception => err
        errored(err)
      end

      def close
        Watchdog.kill(self, :decision_deciding_time_out)
        decisions_to_add.each do |type, args|
          type.create!(args)
        end
        unless decisions_to_add.empty?
          update_status!(:executing)
        end
        refresh
      end

      def refresh
        start_next_action
        completed if all_activities_branches_and_workflows_completed?
      end

      def completed
        Flag.create(name: "#{self.name}_completed".to_sym, workflow: workflow, parent: self, status: :complete)
        super
        schedule_next_decision
      end

      def child_completed(child)
        super
        if child.is_a?(Activity) || child.is_a?(Branch)
          refresh
        end
      end

      def child_errored(child, error)
        super
        errored(error)
      end

      def child_timeout(child, timeout)
        super
        timeout(timeout)
      end

      def errored(error)
        Watchdog.kill(self, :decision_executing_time_out)
        super
      end

      def start_next_action
        with_lock do
          open_events do |event|
            break if any_incomplete_blocking_activities_branches_or_workflows?
            event.start
          end
        end
      end

      def open_events
        Event.where(parent: self, status: :open).each do |event|
          yield event
        end
      end

      def any_incomplete_blocking_activities_branches_or_workflows?
        children.type([Activity, Branch, Workflow]).where(mode: :blocking).not_in(:status => [:complete, :open]).any?
      end

      def all_activities_branches_and_workflows_completed?
        !children.type([Activity, Branch, Workflow]).where(:mode.ne => :fire_and_forget, :status.ne => :complete).any?
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

module WorkflowServer
  module Models
    class Decision < Event

      after_create :enqueue_schedule_next_decision

      def start
        super
        enqueue_send_to_client(max_attempts: 25)
        update_status!(:sent_to_client)
      end

      def restart
        raise WorkflowServer::InvalidEventStatus, "Decision #{self.name} can't transition from #{status} to restarting" unless [:error, :timeout].include?(status)
        update_status!(:restarting)
        cleanup
        start
      end

      def add_decisions(decisions = [])
        raise WorkflowServer::InvalidOperation, "Decisions can only be added to an event in the 'deciding' state" unless status == :deciding
        Watchdog.feed(self, :decision_deciding_time_out)

        new_decisions = decisions.map do |decision|
          new_decision(HashWithIndifferentAccess.new(decision))
        end

        new_decisions.compact!

        if new_decisions.any?{|d| !d.valid?}
          invalid_decisions = new_decisions.select{|d| !d.valid? }
          raise WorkflowServer::InvalidParameters, invalid_decisions.map{|d| {d.event_type => d.errors}}
        else
          new_decisions.each{|d| d.save!}
        end
      end

      def change_status(new_status, args = {})
        return if status == new_status.try(:to_sym)
        case new_status.to_sym
        when :deciding
          raise WorkflowServer::InvalidEventStatus, "Decision #{self.name} can't transition from #{status} to #{new_status}" unless [:sent_to_client, :timeout].include?(status)
          deciding
        when :deciding_complete
          raise WorkflowServer::InvalidEventStatus, "Decision #{self.name} can't transition from #{status} to #{new_status}" unless [:sent_to_client, :deciding, :timeout].include?(status)
          deciding_complete
        when :errored
          raise WorkflowServer::InvalidEventStatus, "Decision #{self.name} can't transition from #{status} to #{new_status}" unless [:sent_to_client, :deciding, :timeout].include?(status)
          errored(args[:error])
        else
          raise WorkflowServer::InvalidEventStatus, "Invalid status #{new_status}"
        end
      end

      def completed
        responsible_for_complete = false
        with_lock do
          # check complete again inside the lock
          if status != :complete
            super
            responsible_for_complete = true
          end
        end
        if responsible_for_complete
          enqueue_schedule_next_decision
        end
      end

      def child_completed(child)
        super
        if child.blocking?
          continue
        else
          complete_if_done
        end
      end

      def errored(error)
        super
      end

      def serializable_hash(options = {})
        hash = super
        hash.merge!(decider: workflow.decider, subject: workflow.subject)
        Marshal.load(Marshal.dump(hash))
      end

      def resumed
        send_to_client
        super
      end

      private

      def deciding
        Watchdog.feed(self, :decision_deciding_time_out)
        update_status!(:deciding)
        self.children.destroy_all
      end

      def deciding_complete
        Watchdog.dismiss(self, :decision_deciding_time_out)
        self.children.any? ? update_status!(:executing) : completed
        enqueue_work_on_decisions
      end

      def work_on_decisions
        reload
        start_next_action
        complete_if_done
      end
      # TODO discuss the pattern of alias_method'ing to continue
      alias_method :continue, :work_on_decisions

      def complete_if_done
        if status != :complete && all_children_done?
          completed
        end
      end

      def new_flag(name)
        Flag.new(name: name, parent: self, workflow: workflow, user: user)
      end

      def new_timer(name, fires_at = Time.now)
        Timer.new(fires_at: fires_at, name: name, parent: self, workflow: workflow, user: user)
      end

      def new_activity(name, options = {})
        Activity.new({name: name, workflow: workflow, parent: self, user: user}.merge(options))
      end

      def new_branch(name, options = {})
        Branch.new({name: name, workflow: workflow, parent: self, user: user}.merge(options))
      end

      def new_workflow(name, workflow_type, subject, decider, options = {})
        Workflow.new({name: name, workflow_type: workflow_type, subject: subject, decider: decider.to_s, workflow: workflow, parent: self, user: user}.merge(options))
      end

      def new_complete_workflow
        WorkflowCompleteFlag.new(name: "#{workflow.name}:complete", parent: self, workflow: workflow, user: user)
      end

      def new_continue_as_new_workflow
        ContinueAsNewWorkflowFlag.new(name: "#{workflow.name}:continue_as_new_workflow", parent: self, workflow: workflow, user: user)
      end

      def new_decision(options = {})
        case options.delete(:type).to_s
        when 'flag'
          new_flag(options[:name])
        when 'timer'
          new_timer(options[:name], options[:fires_at])
        when 'activity'
          new_activity(options.delete(:name), options)
        when 'branch'
          new_branch(options.delete(:name), options)
        when 'workflow'
          new_workflow(options.delete(:name), options.delete(:workflow_type), options.delete(:subject), options.delete(:decider), options)
        when 'complete_workflow'
          new_complete_workflow
        when 'continue_as_new_workflow'
          new_continue_as_new_workflow
        end
      end

      def start_next_action
        open_events do |event|
          break if any_incomplete_blocking_activities_branches_or_workflows?
          event.start
        end
      end

      def open_events
        children.where(status: :open).each do |event|
          yield event
        end
      end

      def any_incomplete_blocking_activities_branches_or_workflows?
        children.type([Activity, Branch, Workflow]).where(mode: :blocking).not_in(:status => [:complete, :open]).any?
      end

      def all_children_done?
        children.not_in(_type: Timer).where(:mode.ne => :fire_and_forget, :status.ne => :complete).none? &&
        children.type(Timer).where(:status => :open, :mode.ne => :fire_and_forget).none?
      end

      def schedule_next_decision
        WorkflowServer.schedule_next_decision(workflow)
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
        begin
          Watchdog.start(self, :decision_deciding_time_out, 12.hours)
          update_status!(:sent_to_client)
          WorkflowServer::Client.make_decision(self)
        rescue => error
          Watchdog.dismiss(self, :decision_deciding_time_out)
          raise
        end
      end

    end
  end
end

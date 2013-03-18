module WorkflowServer
  module Models
    class Decision < Event

      after_create :enqueue_schedule_next_decision

      attr_accessor :decisions_to_add

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

      def change_status(new_status, args = {})
        return if status == new_status.try(:to_sym)
        case new_status.to_sym
        when :deciding
          raise WorkflowServer::InvalidEventStatus, "Decision #{self.name} can't transition from #{status} to #{new_status}" unless [:sent_to_client, :timeout].include?(status)
          deciding
        when :deciding_complete
          raise WorkflowServer::InvalidEventStatus, "Decision #{self.name} can't transition from #{status} to #{new_status}" unless [:sent_to_client, :deciding, :timeout].include?(status)
          self.decisions_to_add = []
          (args[:decisions] || []).each do |decision|
            add_new_decision(HashWithIndifferentAccess.new(decision))
          end
          close
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
        hash.merge!({ history_decisions: past_decisions.where(:inactive.ne => true).map {|decision| {name: decision.name, status: decision.status} }, decider: workflow.decider, subject: workflow.subject})
        Marshal.load(Marshal.dump(hash))
      end

      def resumed
        send_to_client
        super
      end

      private

      def deciding
        update_status!(:deciding)
        Watchdog.feed(self, :decision_deciding_time_out)
      end

      def close
        Watchdog.dismiss(self, :decision_deciding_time_out)
        decisions = decisions_to_add.map do |type, args|
          type.new(args.merge(workflow: workflow, parent: self))
        end

        if decisions.any?{|d| !d.valid?}
          invalid_decisions = decisions.select{|d| !d.valid? }
          raise WorkflowServer::InvalidParameters, invalid_decisions.map{|d| {d.event_type => d.errors}}
        else
          decisions.each{|d| d.save!}
        end
        reload

        unless decisions.empty?
          update_status!(:executing)
        end
        enqueue_work_on_decisions
      end

      def work_on_decisions
        reload
        start_next_action
        complete_if_done
      end
      alias_method :continue, :work_on_decisions

      def complete_if_done
        if status != :complete && all_children_done?
          completed
        end
      end

      def add_flag(name)
        decisions_to_add << [Flag, {name: name, parent: self, workflow: workflow}]
      end

      def add_timer(name, fires_at = Time.now)
        decisions_to_add << [Timer, {fires_at: fires_at, name: name, parent: self, workflow: workflow}]
      end

      def add_activity(name, options = {})
        decisions_to_add << [Activity, {name: name, workflow: workflow, parent: self}.merge(options)]
      end

      def add_branch(name, options = {})
        decisions_to_add << [Branch, {name: name, workflow: workflow, parent: self}.merge(options)]
      end

      def add_workflow(name, workflow_type, subject, decider, options = {})
        decisions_to_add << [Workflow, {name: name, workflow_type: workflow_type, subject: subject, decider: decider.to_s, workflow: workflow, parent: self, user: workflow.user}.merge(options)]
      end

      def complete_workflow
        decisions_to_add << [WorkflowCompleteFlag, {name: "#{workflow.name}:complete", parent: self, workflow: workflow}]
      end

      def continue_as_new_workflow
        decisions_to_add << [ContinueAsNewWorkflowFlag, {name: "#{workflow.name}:continue_as_new_workflow", parent: self, workflow: workflow}]
      end

      def add_new_decision(options = {})
        case options.delete(:type).to_s
        when 'flag'
          add_flag(options[:name])
        when 'timer'
          add_timer(options[:name], options[:fires_at])
        when 'activity'
          add_activity(options.delete(:name), options)
        when 'branch'
          add_branch(options.delete(:name), options)
        when 'workflow'
          add_workflow(options.delete(:name), options.delete(:workflow_type), options.delete(:subject), options.delete(:decider), options)
        when 'complete_workflow'
          complete_workflow
        when 'continue_as_new_workflow'
          continue_as_new_workflow
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
        children.type(Timer).where(:status => :open).none?
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
        WorkflowServer::Client.make_decision(self)
        update_status!(:sent_to_client)
        Watchdog.start(self, :decision_deciding_time_out)
      end

    end
  end
end

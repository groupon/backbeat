module WorkflowServer
  module Models
    class Event
      include Mongoid::Document
      include Mongoid::Timestamps
      include Mongoid::Locker
      include WorkflowServer::Logger
      include Tree

      field :_id,            type: String, default: ->{ UUIDTools::UUID.random_create.to_s }
      field :status,         type: Symbol, default: :open
      field :status_history, type: Array, default: []
      field :name,           type: Symbol

      field :client_data,     type: Hash, default: {}, label: "Clients should use this field to store event specific information e.g. arguments for activities, client library specific options etc."
      field :client_metadata, type: Hash, default: {}, label: "Clients should use this field to store metadata with the events e.g. build version, process pid etc."

      field :inactive,       type: Boolean, default: false
      field :_delayed_jobs,  type: Array, default: []

      auto_increment :sequence

      belongs_to :user, index: true
      belongs_to :workflow, inverse_of: :events, class_name: "WorkflowServer::Models::Workflow", index: true
      belongs_to :parent, inverse_of: :children, class_name: "WorkflowServer::Models::Event", index: true
      has_many :children, inverse_of: :parent, class_name: "WorkflowServer::Models::Event", order: {sequence: 1}, dependent: :destroy

      has_many :watchdogs, inverse_of: :subject, class_name: "WorkflowServer::Models::Watchdog", dependent: :destroy

      index({ status: 1 })
      index({ _type: 1, status: 1 })

      index({ workflow: 1, _type: 1, status: 1 }, { background: true })
      index({ parent: 1, status: 1, mode: 1, _type: 1 }, { background: true })

      before_destroy do
        destroy_jobs
      end

      validates_presence_of :name, :user

      def add_decision(decision_name, orphan = false)
        options = { name: decision_name, workflow: self.workflow, client_data: self.client_data, client_metadata: self.client_metadata, user: user }
        options[:parent] = self unless orphan
        Decision.create!(options)
      end

      def add_interrupt(decision_name, orphan = false)
        decision = add_decision(decision_name, orphan)
        # adding a decision would immediately trigger schedule_next_decision on the workflow. If the workflow ignores the interrupt, start it here.
        workflow.with_lock do
          if decision.reload.status == :open
            decision.start
          end
        end
      end

      def update_status!(new_status, error = nil)
        unless new_status == self.status && new_status != :retrying
          status_hash = {from: self.status, to: new_status, at: Time.now.to_datetime.to_s, tid: WorkflowServer::Logger.tid }
          status_hash[:error] = error_hash(error) if error
          self.status_history << status_hash
          self.status = new_status
          self.save!
        end
      end

      def blocking?
        children.where(:mode.ne => :fire_and_forget, :status.ne => :complete).any?
      end

      def start
        info(id: self.id, name: self.name, type: self.event_type, notification: :start)
        #notify_of("start")
      end

      def restart
        raise 'This event does not support restarting'
      end

      def completed
        update_status!(:complete)
        info(id: self.id, name: self.name, type: self.event_type, notification: :complete)
        #notify_of("complete")
        Watchdog.mass_dismiss(self)
        parent.child_completed(self) if parent
      end

      def paused
        update_status!(:pause)
        Watchdog.mass_dismiss(self)
        parent.child_paused(self) if parent
      end

      def resumed
        parent.child_resumed(self) if parent
      end

      def errored(error)
        update_status!(:error, error)
        notify_of("error", error)
        Watchdog.mass_dismiss(self)
        parent.child_errored(self, error) if parent
      end

      def timeout(timeout)
        update_status!(:timeout, timeout)
        notify_of("timeout", timeout)
        Watchdog.mass_dismiss(self)
        parent.child_timeout(self, timeout) if parent
      end

      def child_completed(child)
      end

      def child_paused(child)
        unless child.respond_to?(:fire_and_forget?) && child.fire_and_forget?
          Watchdog.mass_dismiss(self)
          parent.child_paused(child) if parent
        end
      end

      def child_resumed(child)
        unless child.respond_to?(:fire_and_forget?) && child.fire_and_forget?
          parent.child_resumed(child) if parent
        end
      end

      def child_errored(child, error)
        unless child.respond_to?(:fire_and_forget?) && child.fire_and_forget?
          Watchdog.mass_dismiss(self)
          parent.child_errored(child, error) if parent
        end
      end

      def child_timeout(child, timeout_name)
        unless child.respond_to?(:fire_and_forget?) && child.fire_and_forget?
          Watchdog.mass_dismiss(self)
          parent.child_timeout(child, timeout_name) if parent
        end
      end

      def past_decisions
        workflow.past_decisions(self)
      end

      def notify_of(notification, error = nil)
        error_data = error_hash(error)
        info(id: self.id, name: self.name, type: self.event_type, notification: notification, error: error_data)
        enqueue_notify_client(args: [notification, error_data], max_attempts: 2)
      end

      def notify_client(notification, error_data)
        WorkflowServer::Client.notify_of(self, notification, error_data)
      end

      # TODO - Refactor this. Move it outside in some constants so that other methods can refer to this (like the ones in workflow.rb)
      TYPE_TO_STRING_HASH = {
        'WorkflowServer::Models::Event'                       => 'event',    # We shouldn't ever get this one, but this way we won't blow up if we do
        'WorkflowServer::Models::Activity'                    => 'activity',
        'WorkflowServer::Models::SubActivity'                 => 'activity',
        'WorkflowServer::Models::Branch'                      => 'branch',
        'WorkflowServer::Models::Decision'                    => 'decision',
        'WorkflowServer::Models::Flag'                        => 'flag',
        'WorkflowServer::Models::WorkflowCompleteFlag'        => 'flag',
        'WorkflowServer::Models::ContinueAsNewWorkflowFlag'   => 'flag',
        'WorkflowServer::Models::Signal'                      => 'signal',
        'WorkflowServer::Models::Timer'                       => 'timer',
        'WorkflowServer::Models::Workflow'                    => 'workflow'
      }

      # These fields are not included in the hash sent out to the client
      def self.blacklisted_fields
        ["locked_at", "locked_until", "start_signal", "status_history", "sequence", "client_metadata", "orphan_decision", "inactive", "user_id"]
      end

      def self.hidden_field?(field)
        blacklisted_fields.include?(field) || field.to_s.start_with?("_")
      end

      def serializable_hash(options = {})
        hash = super
        hash.delete_if { |key, value| self.class.hidden_field?(key) }
        hash.merge!({ id: id, type: event_type})
        Marshal.load(Marshal.dump(hash))
      end

      def event_type
        TYPE_TO_STRING_HASH[self.class.to_s]
      end

      def async_jobs
        WorkflowServer::Async::Job.jobs(self)
      end

      def cleanup
        destroy_jobs
        Watchdog.mass_dismiss(self)
      end

      def destroy_jobs
        self.async_jobs.destroy
      end

      def my_user
        workflow.user
      end

      def with_lock_with_defaults(options = {}, &block)
        opts = {retry_sleep: 0.5, retries: 10, timeout: 10}.merge(options)
        with_lock_without_defaults(opts, &block)
      end
      alias_method :with_lock_without_defaults, :with_lock
      alias_method :with_lock, :with_lock_with_defaults

      def parent_decision
        p = self.parent
        @parent_decision ||= loop do
          break p if p.nil? || p.is_a?(Decision)
          p = p.parent
        end
      end

      def method_missing_with_enqueue(name, *args)
        if name.to_s =~ /^(enqueue)_(.*)$/
          begin
            method_name = $2.to_sym
            options = args.first.is_a?(Hash) ? args.first : {}
            max_attempts = options[:max_attempts]
            method_args = options[:args]
            now_time = Time.now
            fires_at = options[:fires_at] || now_time
            job = {event: self, method: method_name, args: method_args, max_attempts: max_attempts}
            if fires_at.to_time <= now_time
              WorkflowServer::Async::Job.enqueue(job)
            else
              WorkflowServer::Async::Job.schedule(job, fires_at)
            end
          rescue Exception => e
            error({ id: id, method_name: name, args: args, error: e, backtrace: e.backtrace })
            raise
          end
        else
          method_missing_without_enqueue(name, *args)
        end
      end
      alias_method_chain :method_missing, :enqueue

      def respond_to_missing_with_enqueue?(method_name, include_private = false)
        if method_name.to_s =~ /^(enqueue)_(.*)$/
          method_name = $2.to_sym
          respond_to?(method_name, include_private)
        else
          respond_to_missing_without_enqueue?(method_name, include_private)
        end
      end
      alias_method_chain :respond_to_missing?, :enqueue

      def self.field_hash
        hash = {
          id: { type: String, label: "uuid" },
          type: { type: String, label: "event type" }
        }
        self.fields.each_pair do |field, data|
          next if hidden_field?(field)
          hash[field] = { type: data.type, label: data.label }
        end
        hash
      end

      private

      def error_hash(error)
        case error
        when StandardError
          error_hash = {error_klass: error.class.to_s, message: error.message}
          if error.backtrace
            error_hash[:backtrace] = error.backtrace
          end
          error_hash
        when String
          {error_klass: error.class.to_s, message: error}
        else
          error
        end if error
      end

    end
  end
end

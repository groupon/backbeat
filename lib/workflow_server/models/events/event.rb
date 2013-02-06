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

      belongs_to :workflow, inverse_of: :events, class_name: "WorkflowServer::Models::Workflow", index: true
      belongs_to :parent, inverse_of: :children, class_name: "WorkflowServer::Models::Event", index: true
      has_many :children, inverse_of: :parent, class_name: "WorkflowServer::Models::Event", order: {created_at: 1}, dependent: :destroy

      index({ status: 1 })

      before_destroy do
        Watchdog.mass_dismiss(self)
        destroy_jobs
      end

      validates_presence_of :name

      def add_decision(decision_name)
        self.children << Decision.create!(name: decision_name, workflow: self.workflow, parent: self)
      end

      def update_status!(new_status, error = nil)
        unless new_status == self.status && new_status != :retrying
          status_hash = {from: self.status, to: new_status, at: Time.now.to_datetime.to_s}
          status_hash[:error] = error_hash(error) if error
          self.status_history << status_hash
          self.status = new_status
          self.save!
        end
      end

      def blocking?
        false
      end

      def start
        notify_of("start")
      end

      def completed
        update_status!(:complete)
        Watchdog.mass_dismiss(self)
        notify_of("complete")
        parent.child_completed(self) if parent
      end

      def errored(error)
        update_status!(:error, error)
        Watchdog.mass_dismiss(self)
        notify_of("error", error)
        parent.child_errored(self, error) if parent
      end

      def timeout(timeout)
        update_status!(:timeout, timeout)
        Watchdog.mass_dismiss(self)
        notify_of("timeout", timeout)
        parent.child_timeout(self, timeout) if parent
      end

      def child_completed(child)

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
          parent.child_errored(child, error) if parent
        end
      end

      def past_flags
        workflow.past_flags(self)
      end

      def notify_of(notification, error = nil)
        error_data = error_hash(error)
        if error_data
          error(notification: notification, error: error_data)
        else
          info(notification: notification, error: error_data)
        end
        WorkflowServer::Async::Job.schedule(event: self, method: :notify_client, args: [notification, error_data], max_attempts: 2)
      end

      def notify_client(notification, error_data)
        WorkflowServer::Client.notify_of(self, notification, error_data)
      end

      # TODO - Refactor this. Move it outside in some constants so that other methods can refer to this (like the ones in workflow.rb)
      TYPE_TO_STRING_HASH = {
        'WorkflowServer::Models::Flag'        => 'flag',
        'WorkflowServer::Models::Workflow'    => 'workflow',
        'WorkflowServer::Models::Signal'      => 'signal',
        'WorkflowServer::Models::Decision'    => 'decision',
        'WorkflowServer::Models::Activity'    => 'activity',
        'WorkflowServer::Models::SubActivity' => 'activity',
        'WorkflowServer::Models::Branch'      => 'branch',
        'WorkflowServer::Models::Timer'       => 'timer'
      }

      # These fields are not included in the hash sent out to the client
      def blacklisted_fields
        ["_id", "_type", "locked_at", "locked_until", "start_signal", "status_history"]
      end

      def serializable_hash(options = {})
        hash = super
        blacklisted_fields.each { |field| hash.delete(field) }
        hash.merge({ id: id, type: event_type})
      end

      def event_type
        TYPE_TO_STRING_HASH[self.class.to_s]
      end

      def async_jobs
        WorkflowServer::Async::Job.jobs(self)
      end

      def destroy_jobs
        self.async_jobs.destroy
      end

      def my_user
        workflow.user
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
        else
          error
        end if error
      end

    end
  end
end

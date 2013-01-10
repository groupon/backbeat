module WorkflowServer
  module Models
    class Event
      include Mongoid::Document
      include Mongoid::Timestamps
      include Mongoid::Locker

      field :status, type: Symbol, default: :open
      field :status_history, type: Array, default: []
      field :name, type: Symbol

      belongs_to :workflow, inverse_of: :events, class_name: "WorkflowServer::Models::Workflow"
      belongs_to :parent, inverse_of: :children, class_name: "WorkflowServer::Models::Event"
      has_many :children, inverse_of: :parent, class_name: "WorkflowServer::Models::Event", order: {created_at: 1}

      validates_presence_of :name

      def add_decision(decision_name)
        Decision.create!(parent: self, name: decision_name, workflow: self.workflow)
      end

      def update_status!(new_status, error = nil)
        unless new_status == self.status && new_status != :retrying
          status_hash = {from: self.status, to: new_status, at: Time.now}
          if error
            error_hash = {error_klass: error.class.to_s, message: error.message}
            if error.backtrace
              error_hash[:backtrace] = error.backtrace
            end
            status_hash[:error] = error_hash
          end
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
        notify_of("complete")
        parent.child_completed(self) if parent
      end

      def errored(error)
        update_status!(:error, error)
        notify_of("error", error)
        parent.child_errored(self, error) if parent
      end

      def timeout(timeout)
        update_status!(:timeout, timeout)
        notify_of("timeout", timeout)
        parent.child_timeout(self, timeout) if parent
      end

      def child_completed(child)

      end

      def child_errored(child, error)

      end

      def child_timeout(child, timeout_name)

      end

      def past_flags
        workflow.past_flags(self)
      end

      def notify_of(notification, error = nil)
        WorkflowServer::AsyncClient.notify_of(self, notification, error)
      end

      def print_name
        "#{status} - #{self.class.to_s.split("::").last} - #{name}"
      end
    end
  end
end
module WorkflowServer
  module Models
    class Event
      include Mongoid::Document
      include Mongoid::Timestamps
      include Mongoid::Locker

      field :_id,            type: String, default: ->{ UUID.generate }
      field :status,         type: Symbol, default: :open
      field :status_history, type: Array, default: []
      field :name,           type: Symbol

      belongs_to :workflow, inverse_of: :events, class_name: "WorkflowServer::Models::Workflow"
      belongs_to :parent, inverse_of: :children, class_name: "WorkflowServer::Models::Event"
      has_many :children, inverse_of: :parent, class_name: "WorkflowServer::Models::Event", order: {created_at: 1}

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
        WorkflowServer::AsyncClient.notify_of(self, notification, error_hash(error))
      end

      def print_name
        "#{status} - #{self.class.to_s.split("::").last} - #{name}"
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

      def serializable_hash(options = {})
        hash = super
        hash.delete("_id")
        hash.delete("_type")
        hash.delete("status_history")
        hash.merge({ id: id, type: event_type})
      end

      def event_type
        TYPE_TO_STRING_HASH[self.class.to_s]
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
module WorkflowServer
  module Models
    class Event
      include Mongoid::Document
      include Mongoid::Timestamps

      field :status, type: Symbol, default: :open
      field :status_history, type: Array, default: []
      field :name, type: Symbol

      belongs_to :workflow
      belongs_to :parent, class_name: "WorkflowServer::Models::Event"
      has_many :children, :inverse_of => :parent, class_name: "WorkflowServer::Models::Event", order: {created_at: 1}

      validates_presence_of :name

      def add_decision(decision_name)
        Decision.create!(parent: self, name: decision_name, workflow: self.workflow)
      end

      def update_status!(new_status, error = nil)
        unless new_status == self.status && new_status != :retrying
          status_hash = {from: self.status, to: new_status, at: Time.now}
          case error
          when NilClass
          when TimeOut
            status_hash[:timeout] = {message: error.message}
          else
            status_hash[:error] = {message: error.message, backtrace: error.backtrace}
          end
          self.status_history << status_hash
          self.status = new_status
          self.save!
        end
      end

      def start
        notify_of("#{name}_start")
      end

      def completed
        notify_of("#{name}_complete")
        parent.child_completed(self) if parent
      end

      def errored(error)
        notify_of_error("#{name}_error", error)
        parent.child_errored(self, error) if parent
      end

      def timeout(timeout)
        notify_of_error("#{name}_timeout", timeout)
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

      def notify_of(event = nil, options = {})
        WorkflowServer::Events.notify_of(event, {type: _type}.merge(options))
      end

      def notify_of_error(event, error, options = {})
        WorkflowServer::Events.notify_of_error(event, error, {type: _type}.merge(options))
      end

      def print_name
        "#{status} - #{self.class.to_s.split("::").last} - #{name}"
      end
    end
  end
end

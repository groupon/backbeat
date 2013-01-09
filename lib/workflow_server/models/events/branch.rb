module WorkflowServer
  module Models
    class Branch < Event

      field :mode, type: Symbol, default: :blocking
      field :retry, type: Integer, default: 3
      field :retry_interval, type: Integer, default: 15.minutes
      field :timeout, type: Integer, default: 0
      field :branches, type: Array, default: []

      validate :always_blocking

      def always_blocking
        errors.add(:mode, 'Branches must always be blocking.') if mode != :blocking
      end

      def blocking?
        mode == :blocking
      end

      def start
        super
        WorkflowServer::AsyncClient.evaluate_branch(id)
        Watchdog.start(self, :timeout, timeout) if timeout > 0
        update_status!(:executing)
      end

      def completed(name)
        with_lock do
          Watchdog.kill(self)
          invalid_branch(name) unless branches.include?(name)
          add_decision(name)
          super()
        end
      end

      def invalid_branch(name)
        super.errored(InvalidBranchSelection.new("Branch:#{id} tried to branch to #{name} but is only allowed to branch to #{branches}."))
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
          Watchdog.feed(self) if timeout > 0
        else
          Watchdog.kill(self)
          super
        end
      end

      def retry?
        status_history.find_all {|s| s[:to] == :retrying }.count < self.retry
      end

      def print_name
        super + " - #{name}"
      end

    end
  end
end

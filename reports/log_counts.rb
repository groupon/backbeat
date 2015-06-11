require_relative 'report_base'
module Reports
  class LogCounts < ReportBase
    include Backbeat::Logging

    def perform( options = {} )
      log_queue_counts
      log_ready_nodes
    end

    private

    def log_queue_counts
      log_count(:queue, "retry", Sidekiq::RetrySet.new.size)
      log_count(:queue, "schedule", Sidekiq::ScheduledSet.new.size)

      Sidekiq::Stats.new.queues.each do |queue, size|
        log_count(:queue, queue, size)
      end
    end

    def log_ready_nodes
      ready_nodes_count = Backbeat::Node.where(current_server_status: :ready).count
      log_count(:nodes, :ready_nodes, ready_nodes_count)
    end

    def log_count(type, subject, count)
      info({source: self.class.to_s, type: type, subject: subject, count: count || 0 })
    end
  end
end

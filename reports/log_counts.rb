require_relative 'report_base'
module Reports
  class LogCounts < ReportBase
    include Backbeat::Logging

    def perform( options = {} )
      log_queue_counts
    end

    private

    def log_queue_counts
      log_count(:queue, "retry", Sidekiq::RetrySet.new.size)
      log_count(:queue, "schedule", Sidekiq::ScheduledSet.new.size)

      Sidekiq::Stats.new.queues.each do |queue, size|
        log_count(:queue, queue, size)
      end
    end

    def log_count(type, subject, count)
      info({source: self.class.to_s, type: type, subject: subject, count: count || 0 })
    end
  end
end

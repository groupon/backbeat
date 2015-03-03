require_relative 'report_base'
module Reports
  class LogQueueCounts < ReportBase
    include WorkflowServer::Logger

    def perform( options = {} )
      log_queue_count("retry", Sidekiq::RetrySet.new.size)
      log_queue_count("schedule", Sidekiq::ScheduledSet.new.size)

      Sidekiq::Stats.new.queues.each do |queue, size|
        log_queue_count(queue,size)
      end
    end

    def log_queue_count(name, size)
      info({source: self.class.to_s, queue_name: name, size: size })
    end
  end
end

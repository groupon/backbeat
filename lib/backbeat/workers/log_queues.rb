require 'sidekiq'
require 'sidekiq/schedulable'

module Backbeat
  module Workers
    class LogQueues
      include Logging
      include Sidekiq::Worker
      include Sidekiq::Schedulable

      sidekiq_options retry: false, queue: Config.options[:async_queue]
      sidekiq_schedule Config.options[:schedules][:log_queues]

      def perform
        log_count(:queue, "retry", Sidekiq::RetrySet.new.size)
        log_count(:queue, "schedule", Sidekiq::ScheduledSet.new.size)

        Sidekiq::Stats.new.queues.each do |queue, size|
          log_count(:queue, queue, size)
        end
      end

      private

      def log_count(type, subject, count)
        info({ type: type, subject: subject, count: count || 0 })
      end
    end
  end
end

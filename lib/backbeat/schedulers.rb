require 'backbeat/instrument'

module Backbeat
  module Schedulers
    class AsyncEvent
      def initialize(&timer)
        @timer = timer
      end

      def call(event, node)
        time = @timer.call(node)
        Workers::AsyncWorker.schedule_async_event(event, node, { time: time })
      end
    end

    ScheduleNow = AsyncEvent.new { Time.now }
    ScheduleAt  = AsyncEvent.new { |node| node.fires_at }

    ScheduleRetry = AsyncEvent.new do |node|
      tries = 4 - node.retries_remaining
      tries = 0 if tries < 0
      backoff = (tries ** 4) + node.retry_interval + (rand(30) * (tries + 1))
      Time.now + backoff.minutes
    end

    class PerformEvent
      def self.call(event, node)
        Instrument.instrument(event.name, { node: node }) do
          event.call(node)
        end
      end
    end
  end
end

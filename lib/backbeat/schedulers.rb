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
    ScheduleIn  = AsyncEvent.new { |node| Time.now + node.retry_interval.minutes }

    class PerformEvent
      def self.call(event, node)
        Instrument.instrument(event.name, { node: node }) do
          event.call(node)
        end
      end
    end
  end
end

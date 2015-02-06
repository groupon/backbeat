module V2
  module Schedulers
    class NowScheduler
      def initialize(retries)
        @retries = retries
      end

      def self.schedule(event, node)
        new(0).schedule(event, node)
      end

      def schedule(event, node)
        message = { server_retries_remaining: @retries }
        Instrument.instrument(node, event.name, message) do
          begin
            event.call(node)
          rescue => e
            Server.server_error(event, node, message.merge(error: e))
            raise e
          end
        end
      end
    end

    class RetryScheduler
      def initialize(retries)
        @retries = retries
      end

      def self.schedule(event, node)
        new(0).schedule(event, node)
      end

      def schedule(event, node)
        Workers::AsyncWorker.schedule_async_event(
          event,
          node,
          Time.now + 30.seconds,
          @retries
        )
      end
    end

    class AtScheduler
      def self.schedule(event, node)
        Workers::AsyncWorker.schedule_async_event(event, node, node.fires_at)
      end
    end

    class IntervalScheduler
      def self.schedule(event, node)
        Workers::AsyncWorker.schedule_async_event(
          event,
          node,
          Time.now + node.retry_interval.minutes
        )
      end
    end

    class AsyncScheduler
      def self.schedule(event, node)
        Workers::AsyncWorker.schedule_async_event(event, node, Time.now)
      end
    end
  end
end

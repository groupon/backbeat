module V2
  module Schedulers
    class BaseAsyncEvent
      DEFAULT_RETRIES = 4

      def initialize(&timer)
        @timer = timer
      end

      def call(event, node, retries = DEFAULT_RETRIES)
        time = @timer.call(node)
        Workers::AsyncWorker.schedule_async_event(event, node, time, retries)
      end
    end

    AsyncEvent = BaseAsyncEvent.new { Time.now }
    AsyncEventAt = BaseAsyncEvent.new { |node| node.fires_at }
    AsyncEventBackoff = BaseAsyncEvent.new { Time.now + 30.seconds }
    AsyncEventInterval = BaseAsyncEvent.new { |node| Time.now + node.retry_interval.minutes }

    class PerformEvent
      def initialize(retries)
        @retries = retries
      end

      def self.call(event, node)
        new(0).call(event, node)
      end

      def call(event, node)
        Instrument.instrument(node, event.name, message) do
          begin
            event.call(node)
          rescue => e
            handle_error(event, node, e)
            raise e
          end
        end
      end

      private

      attr_reader :retries

      def handle_error(event, node, error)
        if retries > 0
          AsyncEventBackoff.call(event, node, retries - 1)
        else
          StateManager.call(node, current_server_status: :errored)
          Client.notify_of(node, "error", error)
        end
      end

      def message
        { server_retries_remaining: retries }
      end
    end
  end
end

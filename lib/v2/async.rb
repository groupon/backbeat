module V2
  module Async
    class AsyncEvent
      def self.new(&block)
        Class.new do
          attr_reader :options

          def self.call(event, node)
            new({}).call(event, node)
          end

          def initialize(options)
            @options = options
          end

          define_method(:get_time) do |node|
            block.call(node)
          end

          def call(event, node)
            time = get_time(node)
            Workers::AsyncWorker.schedule_async_event(event, node, options.merge(time: time))
          end
        end
      end
    end

    ScheduleNow = AsyncEvent.new { Time.now }
    ScheduleAt  = AsyncEvent.new { |node| node.fires_at }
    ScheduleIn  = AsyncEvent.new { |node| Time.now + node.retry_interval.minutes }
    Backoff     = AsyncEvent.new { Time.now + 30.seconds }

    class PerformEvent
      DEFAULT_RETRIES = 4

      def initialize(options)
        @options = options
        @retries = options.fetch(:retries, DEFAULT_RETRIES)
      end

      def self.call(event, node)
        new({ retries: 0 }).call(event, node)
      end

      def call(event, node)
        event_data = { node: node, server_retries_remaining: retries }
        Instrument.instrument(event.name, event_data) do
          begin
            event.call(node)
          rescue V2::InvalidClientStatusChange
            raise
          rescue => e
            handle_error(event, node, e)
            raise e
          end
        end
      end

      private

      attr_reader :retries, :options

      def handle_error(event, node, error)
        if retries > 0
          Backoff.new(
            options.merge(retries: retries - 1)
          ).call(event, node)
        else
          StateManager.call(node, current_server_status: :errored)
          Client.notify_of(node, "error", error)
        end
      end
    end
  end
end

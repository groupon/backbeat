module Backbeat
  module Web
    module Middleware
      class SidekiqStats
        def initialize(app)
          @app = app
        end

        ENDPOINT = '/sidekiq_stats'

        def call(env)
          if env['PATH_INFO'] == ENDPOINT
            stats = Sidekiq::Stats.new
            history = Sidekiq::Stats::History.new(1)
            data = {
              latency: stats.queues.keys.inject({}) {|h,q| h[q] = Sidekiq::Queue.new(q).latency; h },
              today: {
                processed: history.processed.values[0],
                failed: history.failed.values[0]
              },
              processed: stats.processed,
              failed: stats.failed,
              enqueued: stats.enqueued,
              scheduled: stats.scheduled_size,
              retry_size: stats.retry_size
            }
            [200, {"Content-Type" => "application/json"}, [data.to_json]]
          else
            @app.call(env)
          end
        end
      end
    end
  end
end

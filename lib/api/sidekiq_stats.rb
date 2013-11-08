module Api
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
            processed: history.processed,
            failed: history.failed
          },
          processed: stats.processed,
          failed: stats.failed,
          enqueued: stats.enqueued,
          scheduled: stats.scheduled_size,
          retry_size: stats.retry_size
        }
        return [ 200, {"Content-Type" => "application/json"}, [ data.to_json ] ]
      end
      status, headers, body = @app.call(env)
      [status, headers, body]
    end
  end
end

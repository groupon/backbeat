module Api
  class SidekiqLatency
    def initialize(app)
      @app = app
    end

    ENDPOINT = '/sidekiq_latency'
    def call(env)
      if env['PATH_INFO'] == ENDPOINT
        return [ 200, {"Content-Type" => "text/plain"}, [ Sidekiq::Queue.new.latency.to_s ] ]
      end
      status, headers, body = @app.call(env)
      [status, headers, body]
    end
  end
end

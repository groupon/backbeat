module Api
  class Health
    def initialize(app)
      @app = app
    end

    ENDPOINT = '/health'.freeze
    def call(env)
      if env['PATH_INFO'] == ENDPOINT
        db_ok = Mongoid.default_session.cluster.nodes.map(&:connected?).uniq == [true]

        result = {
          sha: GIT_REVISION,
          time: Time.now.iso8601,
          status: db_ok ? 'OK' : 'DATABASE_UNREACHABLE'
        }
        return [ 200, {"Content-Type" => "application/json"}, [result.to_json] ]
      end

      status, headers, body = @app.call(env)
      [status, headers, body]
    end
  end
end

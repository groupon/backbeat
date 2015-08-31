module Backbeat
  module Web
    module Middleware
      class Health
        def initialize(app)
          @app = app
        end

        ENDPOINT = '/health'.freeze

        def call(env)
          if env['PATH_INFO'] == ENDPOINT
            db_ok = ActiveRecord::Base.connected?

            result = {
              sha: Config.revision,
              time: Time.now.iso8601,
              status: db_ok ? 'OK' : 'DATABASE_UNREACHABLE'
            }
            [200, {"Content-Type" => "application/json"}, [result.to_json]]
          else
            @app.call(env)
          end
        end
      end
    end
  end
end

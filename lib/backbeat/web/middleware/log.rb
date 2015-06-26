module Backbeat
  module Web
    module Middleware
      class Log
        TRANSACTION_ID_HEADER = 'X-backbeat-tid'.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          t0 = Time.now
          tid = Logger.tid(:set)

          Logger.info("START - Endpoint #{env['PATH_INFO']}")

          envs = env['PATH_INFO'].split("/")
          status, headers, body = response = @app.call(env)

          Logger.info(
            response: {
              status: status,
              type: envs[2],
              method: envs.last,
              env: env['PATH_INFO'],
              duration: Time.now - t0,
              route_info: route_info(env)
            }
          )

          headers[TRANSACTION_ID_HEADER] = tid
          Logger.tid(:clear)

          response
        end

        def route_info(env)
          route_info = env["rack.routing_args"].try(:[], :route_info)
          if route_info
            options = route_info.instance_variable_get("@options")
            options.slice(:version, :namespace, :method, :path)
          end
        end
      end
    end
  end
end

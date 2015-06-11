module Backbeat
  module Web
    module Middleware
      class Log
        include Logging

        TRANSACTION_ID_HEADER = 'X-backbeat-tid'.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          t0 = Time.now
          tid = Backbeat::Logging.tid(:set)
          info "START - Endpoint #{env['PATH_INFO']}"
          envs = env['PATH_INFO'].split("/")
          status, headers, body = @app.call(env)

          info(response: {
            status: status,
            type: envs[2],
            method: envs.last,
            env: env['PATH_INFO'],
            duration: Time.now - t0,
            route_info: route_info(env)})

          headers[TRANSACTION_ID_HEADER] = tid
          Backbeat::Logging.tid(:clear)
          [status, headers, body]
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

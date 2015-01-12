module Api
  module Middleware
    class Log
      include WorkflowServer::Logger

      TRANSACTION_ID_HEADER = 'X-backbeat-tid'.freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        t0 = Time.now
        tid = WorkflowServer::Logger.tid(:set)
        info "START - Endpoint #{env['PATH_INFO']}"
        envs = env['PATH_INFO'].split("/")
        status, headers, body = @app.call(env)

        info( response: { status: status,
                          type: envs[1],
                          method: envs.last,
                          env: env['PATH_INFO'],
                          duration: Time.now - t0})

        headers[TRANSACTION_ID_HEADER] = tid
        WorkflowServer::Logger.tid(:clear)
        [status, headers, body]
      end
    end
  end
end

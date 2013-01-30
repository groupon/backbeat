module Api
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
      status, headers, body = @app.call(env)
      info "END - Time taken #{Time.now - t0}s"
      headers[TRANSACTION_ID_HEADER] = tid
      WorkflowServer::Logger.tid(:clear)
      [status, headers, body]
    end
  end
end
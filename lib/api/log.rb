module Api
  class Log

    include WorkflowServer::Logger

    TRANSACTION_ID_HEADER = 'X-backbeat-tid'.freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      tid = WorkflowServer::Logger.tid(:set)
      info "Request started with #{tid}"
      status, headers, body = @app.call(env)
      info "Request ended with #{tid}"
      headers[TRANSACTION_ID_HEADER] = tid
      WorkflowServer::Logger.tid(:clear)
      [status, headers, body]
    end

  end
end
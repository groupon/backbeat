module Api
  class Health

    def initialize(app)
      @app = app
    end

    def call(env)
      if env['PATH_INFO'].match /\/health/i
        return [ 200, {"Content-Type" => "text/plain"}, [WorkflowServer::Models::Workflow.last.try(:created_at).to_s] ]
      end
      status, headers, body = @app.call(env)
      [status, headers, body]
    end
  end
end
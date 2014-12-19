module Api
  module Middleware
    class Authenticate
      def initialize(app)
        @app = app
      end

      def call(env)
        client_id = env['HTTP_CLIENT_ID']
        env['WORKFLOW_CURRENT_USER'] = WorkflowServer::Models::User.where(id: client_id).first || V2::User.where(id: client_id).first
        return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] unless env['WORKFLOW_CURRENT_USER']
        @app.call(env)
      end
    end
  end
end

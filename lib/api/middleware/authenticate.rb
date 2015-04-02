module Api
  module Middleware
    class Authenticate
      def initialize(app)
        @app = app
      end

      def call(env)
        client_id = env['HTTP_CLIENT_ID']
        env['WORKFLOW_CURRENT_USER'] = user(client_id, env['PATH_INFO'])
        return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] unless env['WORKFLOW_CURRENT_USER']
        @app.call(env)
      end

      private

      def user(client_id, path)
        if path =~ /v2/
          V2::User.where(id: client_id).first
        else
          WorkflowServer::Models::User.where(id: client_id).first
        end
      end
    end
  end
end

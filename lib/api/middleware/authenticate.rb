module Api
  module Middleware
    class Authenticate
      def initialize(app)
        @app = app
      end

      def user_model
        if ::App.v2?
          V2::User
        else
          WorkflowServer::Models::User
        end
      end

      def call(env)
        client_id = env['HTTP_CLIENT_ID']
        env['WORKFLOW_CURRENT_USER'] = user_model.where(id: client_id).first
        return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] unless env['WORKFLOW_CURRENT_USER']
        @app.call(env)
      end
    end
  end
end

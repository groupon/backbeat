module Api
  module Middleware
    class Authenticate
      def initialize(app)
        @app = app
      end

      def call(env)
        client_id = env['HTTP_CLIENT_ID']
        env['WORKFLOW_CURRENT_USER'] = user(client_id)
        return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] unless env['WORKFLOW_CURRENT_USER']
        @app.call(env)
      end

      private

      def user(client_id)
        if Backbeat.v2?
          V2::User.where(uuid: client_id).first
        else
          WorkflowServer::Models::User.where(id: client_id).first
        end
      end
    end
  end
end

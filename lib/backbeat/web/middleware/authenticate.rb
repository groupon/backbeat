module Backbeat
  module Web
    module Middleware
      class Authenticate
        def initialize(app)
          @app = app
        end

        def call(env)
          client_id = env['HTTP_CLIENT_ID']
          user = find_user(client_id)
          return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] unless user
          env['WORKFLOW_CURRENT_USER'] = user
          @app.call(env)
        end

        private

        def find_user(id)
          User.find(id)
        rescue
          false
        end
      end
    end
  end
end

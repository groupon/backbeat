require 'workflow_server'
module Api
  class Authenticate
    def initialize(app)
      @app = app
    end

    def call(env)
      client_id = env['HTTP_CLIENT_ID']
      return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] if client_id.nil? || !WorkflowServer::Models::User.where(client_id: client_id).exists?
      env['WORKFLOW_CURRENT_USER'] = WorkflowServer::Models::User.find_by(client_id: client_id)
      @app.call(env)
    end

  end
end
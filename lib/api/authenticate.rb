require 'workflow_server'
module Api
  class Authenticate

    include ::Goliath::Rack::AsyncMiddleware

    def call(env)
      client_id = env['HTTP_CLIENT_ID']
      return [401, {}, "Unauthorized"] if client_id.nil? || !WorkflowServer::Models::User.where(client_id: client_id).exists?
      env['WORKFLOW_CURRENT_USER'] = WorkflowServer::Models::User.find_by(client_id: client_id)
      super(env)
    end

  end
end
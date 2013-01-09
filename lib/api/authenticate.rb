require 'workflow_server'
module Api
  class Authenticate

    include ::Goliath::Rack::AsyncMiddleware

    def call(env)
      client_id = env['HTTP_CLIENTID']
      return [401, {}, "Unauthorized client"] if client_id.nil? || !WorkflowServer::Models::User.where(id: client_id).exists?
      env['WORKFLOW_CURRENT_USER'] = WorkflowServer::Models::User.find(client_id)
      super(env)
    end

  end
end
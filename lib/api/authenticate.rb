require 'newrelic_rpm'
require 'new_relic/agent/instrumentation/rack'

module Api
  class Authenticate
    def initialize(app)
      @app = app
    end

    def call(env)
      client_id = env['HTTP_CLIENT_ID']
      env['WORKFLOW_CURRENT_USER'] = WorkflowServer::Models::User.where(id: client_id).first
      return [401, {"Content-Type"=>"text/plain"}, ["Unauthorized"]] unless env['WORKFLOW_CURRENT_USER']
      @app.call(env)
    end

    include ::NewRelic::Agent::Instrumentation::Rack
  end
end

require 'grape'
require 'workflow_server'

module Api
  class Workflow < Grape::API
    format :json

    helpers do
      def current_user
        @current_user ||= env['WORKFLOW_CURRENT_USER']
      end
    end

    resource 'workflows' do
      params do
        requires :workflow_type, :type => String, :desc => 'Require a workflow type'
        requires :subject_type,  :type => String, :desc => 'Require a subject type'
        requires :subject_id,    :type => String, :desc => 'Require a subject id'
        requires :decider,       :type => String, :desc => 'Require a workflow decider'
      end

      post "/" do
        params[:user] = current_user
        wf = WorkflowServer::Manager.find_or_create_workflow(params)
        [201, {}, wf]
      end
    end
  end
end
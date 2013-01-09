require 'grape'
require 'workflow_server'

module Api
  class Workflow < Grape::API
    format :json

    rescue_from WorkflowServer::EventNotFound do |e|
      Rack::Response.new([ e.message ], 404, { "Content-type" => "text/error" }).finish
    end

    rescue_from WorkflowServer::EventComplete do |e|
      Rack::Response.new([ e.message ], 400, { "Content-type" => "text/error" }).finish
    end

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

      get "/:id" do
        wf = current_user.workflows.find(params[:id])
        raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:id]}) not found" unless wf
        [200, {}, wf]
      end

      post "/:id/signal/:name" do
        wf = current_user.workflows.find(params[:id])
        raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:id]}) not found" unless wf
        signal = wf.signal(params[:name])
        [201, {}, signal]
      end
    end
  end
end
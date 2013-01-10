require 'grape'
require 'workflow_server'

module Api
  class Workflow < Grape::API
    format :json

    rescue_from :all do |e|
      Rack::Response.new({error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventNotFound do |e|
      Rack::Response.new({error: e.message }.to_json, 404, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventComplete, WorkflowServer::InvalidParameters, WorkflowServer::InvalidEventStatus, WorkflowServer::InvalidDecisionSelection do |e|
      Rack::Response.new({error: e.message }.to_json, 400, { "Content-type" => "application/json" }).finish
    end

    helpers do
      def current_user
        @current_user ||= env['WORKFLOW_CURRENT_USER']
      end
    end

    resource 'workflows' do
      post "/" do
        params[:user] = current_user
        wf = WorkflowServer::Manager.find_or_create_workflow(params)

        if wf.valid?
          wf
        else
          raise WorkflowServer::InvalidParameters, wf.errors.to_hash
        end
      end

      get "/:id" do
        wf = current_user.workflows.find(params[:id])
        raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:id]}) not found" unless wf
        wf
      end

      [:flags, :signals, :activities, :timers, :events].each do |event_type|
        get "/:id/#{event_type}" do
          wf = current_user.workflows.find(params[:id])
          raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:id]}) not found" unless wf
          wf.__send__(event_type)
        end
      end

      post "/:id/signal/:name" do
        wf = current_user.workflows.find(params[:id])
        raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:id]}) not found" unless wf
        signal = wf.signal(params[:name])
        signal
      end


      segment '/:workflow_id' do
        resource 'events' do
          put "/:id/change_status" do
            wf = current_user.workflows.find(params[:workflow_id])
            raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:workflow_id]}) not found" unless wf

            event = wf.events.find(params[:id])
            raise WorkflowServer::EventNotFound, "Event with id(#{params[:id]}) not found" unless event

            event.change_status(params[:status], HashWithIndifferentAccess.new(JSON.parse(params[:args] || "{}")))
          end

          put "/:id/run_sub_activity" do
            wf = current_user.workflows.find(params[:workflow_id])
            raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:workflow_id]}) not found" unless wf

            event = wf.activities.find(params[:id])
            raise WorkflowServer::EventNotFound, "Event with id(#{params[:id]}) not found" unless event

            sub_activity = event.run_sub_activity(HashWithIndifferentAccess.new(JSON.parse(params[:sub_activity] || "{}")))
            if sub_activity.blocking?
              header("WAIT_FOR_SUB_ACTIVITY", "true")
            end
            sub_activity
          end
        end
      end
    end
  end
end
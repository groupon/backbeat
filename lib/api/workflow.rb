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

    rescue_from WorkflowServer::EventComplete, WorkflowServer::InvalidParameters, WorkflowServer::InvalidEventStatus do |e|
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
          [201, {}, wf]
        else
          raise WorkflowServer::InvalidParameters, wf.errors.to_hash
        end
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


      segment '/:workflow_id' do
        resource 'events' do
          put "/:id/change_status" do
            wf = current_user.workflows.find(params[:workflow_id])
            raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:workflow_id]}) not found" unless wf

            event = wf.events.find(params[:id])
            raise WorkflowServer::EventNotFound, "Event with id(#{params[:id]}) not found" unless event

            event.change_status(params[:status], JSON.parse(params[:args] || "[]"))
            [200, {}, ""]
          end

          put "/:id/run_sub_activity" do
            wf = current_user.workflows.find(params[:workflow_id])
            raise WorkflowServer::EventNotFound, "Workflow with id(#{params[:workflow_id]}) not found" unless wf

            event = wf.activities.find(params[:id])
            raise WorkflowServer::EventNotFound, "Event with id(#{params[:id]}) not found" unless event

            sub_activity = event.run_sub_activity(HashWithIndifferentAccess.new(JSON.parse(params[:sub_activity] || "{}")))
            headers = {}
            if sub_activity.blocking?
              headers["WAIT_FOR_SUB_ACTIVITY"] = true
            end
            [200, headers, ""]
          end
        end
      end
    end
  end
end
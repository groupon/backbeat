require 'grape'

module Api
  class Workflow < Grape::API
    include WorkflowServer::Logger
    # formatter :camel_json, Api::CamelJsonFormatter
    # content_type :camel_json, 'application/json'
    # format :camel_json

    format :json

    before do
      ::WorkflowServer::Helper::HashKeyTransformations.underscore_keys(params)
    end

    rescue_from :all do |e|
      Api::Workflow.error(e)
      Rack::Response.new({error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventNotFound do |e|
      Api::Workflow.error(e)
      Rack::Response.new({error: e.message }.to_json, 404, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventComplete, WorkflowServer::InvalidParameters, WorkflowServer::InvalidEventStatus, WorkflowServer::InvalidDecisionSelection, Grape::Exceptions::ValidationError do |e|
      Api::Workflow.error(e)
      Rack::Response.new({error: e.message }.to_json, 400, { "Content-type" => "application/json" }).finish
    end

    helpers do
      def current_user
        @current_user ||= env['WORKFLOW_CURRENT_USER']
      end

      def find_workflow(id)
        wf = current_user.workflows.find(id)
        raise WorkflowServer::EventNotFound, "Workflow with id(#{id}) not found" unless wf
        wf
      end

      def find_event(event_id, workflow_id = nil, event_type = nil)
        event = nil
        if workflow_id
          wf = find_workflow(workflow_id)
          event_type ||= :events #all events
          event = wf.__send__(event_type).find(event_id)
          raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found" unless event
        else
          event = WorkflowServer::Models::Event.find(event_id)
          unless event && event.workflow.user == current_user
            raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found"
          end
        end
        event
      end
    end

    resource 'workflows' do
      post "/" do
        params[:user] = current_user
        wf = WorkflowServer.find_or_create_workflow(params)

        if wf.valid?
          wf
        else
          raise WorkflowServer::InvalidParameters, wf.errors.to_hash
        end
      end

      get "/" do
        query = {}
        [:workflow_type, :decider, :subject_klass, :subject_id].each do |query_param|
          if params.include?(query_param)
            query[query_param] = params[query_param]
          end
        end
        current_user.workflows.where(query).map {|wf| wf }
      end

      get "/:id" do
        find_workflow(params[:id])
      end

      [:flags, :signals, :activities, :timers, :events].each do |event_type|
        get "/:id/#{event_type}" do
          wf = find_workflow(params[:id])
          wf.__send__(event_type)
        end
      end

      get "/:id/tree" do
        wf = find_workflow(params[:id])
        wf.tree
      end

      #TODO test this endpoint
      get "/:id/tree/print" do
        wf = find_workflow(params[:id])
        {print: wf.tree.print(true)}
      end

      get "/:id/big_tree" do
        wf = find_workflow(params[:id])
        wf.big_tree
      end

      post "/:id/signal/:name" do
        wf = find_workflow(params[:id])
        signal = wf.signal(params[:name])
        signal
      end


      segment '/:workflow_id' do
        resource 'events' do
          get "/:id" do
            find_event(params[:id], params[:workflow_id])
          end

          get "/:id/tree" do
            e = find_event(params[:id], params[:workflow_id])
            e.tree
          end

          #TODO test this endpoint
          get "/:id/tree/print" do
            e = find_event(params[:id], params[:workflow_id])
            {print: e.tree.print(true)}
          end

          get "/:id/big_tree" do
            e = find_event(params[:id], params[:workflow_id])
            e.big_tree
          end

          put "/:id/status/:new_status" do
            event = find_event(params[:id], params[:workflow_id])
            raise WorkflowServer::InvalidParameters, "args parameter is invalid" if params[:args] && !params[:args].is_a?(Hash)
            event.change_status(params[:new_status], params[:args] || {})
            {success: true}
          end

          params do
            requires :sub_activity, type: Hash, :desc => 'sub activity param cannot be empty'
          end
          put "/:id/run_sub_activity" do
            event = find_event(params[:id], params[:workflow_id], :activities)
            sub_activity = event.run_sub_activity(params[:sub_activity] || {})
            if sub_activity.try(:blocking?)
              header("WAIT_FOR_SUB_ACTIVITY", "true")
            end
            sub_activity
          end
        end
      end
    end
    resource "events" do
      get "/:id" do
        find_event(params[:id])
      end

      get "/:id/tree" do
        e = find_event(params[:id])
        e.tree
      end

      #TODO test this endpoint
      get "/:id/tree/print" do
        e = find_event(params[:id])
        {print: e.tree.print(true)}
      end

      get "/:id/big_tree" do
        e = find_event(params[:id])
        e.big_tree
      end
    end
  end
end

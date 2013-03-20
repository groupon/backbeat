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
      Api::Workflow.error({ error: e, backtrace: e.backtrace })
      Rack::Response.new({error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventNotFound do |e|
      Api::Workflow.error(e)
      Rack::Response.new({error: e.message }.to_json, 404, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventComplete, WorkflowServer::InvalidParameters, WorkflowServer::InvalidEventStatus, WorkflowServer::InvalidDecisionSelection, Grape::Exceptions::Validation do |e|
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

      def find_event(params, event_type = nil)
        event = nil
        event_id = params[:id]
        workflow_id = params[:workflow_id]
        if workflow_id
          wf = find_workflow(workflow_id)
          event_type ||= :events #all events
          event = wf.__send__(event_type).find(event_id)
          raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found" unless event
        else
          event = WorkflowServer::Models::Event.find(event_id)
          unless event && event.my_user == current_user
            raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found"
          end
        end
        event
      end

      # This takes a leaf out of http://docs.mongodb.org/manual/reference/sql-aggregation-comparison/
      # We do not have an api to express this query in Mongoid. This goes out directly through the moped api's
      def group_by_and_having(selector, field, count, greater = true)
        result = WorkflowServer::Models::Event.collection.aggregate(
         { '$match' => selector },
         { '$group' => { '_id' =>  "$#{field}", 'count' => { '$sum' => 1 } } },
         { '$match' => { 'count' => { greater ? '$gt' : '$lt' => count } } })

        result.map { |hash| hash['_id'] }
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

      params do
        requires :run_at, type: String, :desc => 'Timers need a run_at parameter'
      end
      put "/:id/backfill/timer/:name" do
        workflow = find_workflow(params[:id])
        WorkflowServer::Models::Timer.create!(name: params[:name], workflow: workflow, fires_at: params[:run_at]).start
        { success: true }
      end

      put "/:id/backfill/decision/:name" do
        workflow = find_workflow(params[:id])
        signal = WorkflowServer::Models::Signal.create!(name: params[:name], workflow: workflow, status: :complete)
        decision = WorkflowServer::Models::Decision.create!(name: params[:name], workflow: workflow, status: :complete, parent: signal)
        { success: true }
      end

      put "/" do
        query = {}
        [:workflow_type, :decider, :subject].each do |query_param|
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

      get "/:id/tree/print" do
        wf = find_workflow(params[:id])
        {print: wf.tree_to_s}
      end

      post "/:id/signal/:name" do
        wf = find_workflow(params[:id])
        signal = wf.signal(params[:name])
        signal
      end

      put "/:id/pause" do
        wf = find_workflow(params[:id])
        wf.pause
        {success: true}
      end

      put "/:id/resume" do
        wf = find_workflow(params[:id])
        wf.resume
        {success: true}
      end
    end

    # Events can be reached using two url's
    # 1) as a subresource /workflows/<workflow_id>/events/<id>
    # 2) or as a top level resource /events/<id>
    # This proc here is the general declaration that is at the end consumed by both the above endpoints.
    EventSpecification = Proc.new do
      get "/:id" do
        find_event(params)
      end

      put "/:id/restart" do
        e = find_event(params)
        e.restart
        {success: true}
      end

      get "/:id/tree" do
        e = find_event(params)
        e.tree
      end

      get "/:id/tree/print" do
        e = find_event(params)
        {print: e.tree_to_s}
      end

      put "/:id/status/:new_status" do
        event = find_event(params)
        raise WorkflowServer::InvalidParameters, "args parameter is invalid" if params[:args] && !params[:args].is_a?(Hash)
        event.change_status(params[:new_status], params[:args] || {})
        {success: true}
      end

      params do
        requires :sub_activity, type: Hash, :desc => 'sub activity param cannot be empty'
      end
      put "/:id/run_sub_activity" do
        event = find_event(params, :activities)
        sub_activity = event.run_sub_activity(params[:sub_activity] || {})
        if sub_activity.try(:blocking?)
          header("WAIT_FOR_SUB_ACTIVITY", "true")
        end
        sub_activity
      end
    end

    resource 'workflows' do
      segment '/:workflow_id' do
        resource 'events' do
          EventSpecification.call
        end
      end
    end
    resource "events" do
      EventSpecification.call
    end

    namespace 'debug' do

      desc 'returns workflows that have something in error/timeout state'
      get '/error_workflows' do
        ids = current_user.workflows.where(:status.ne => :pause).pluck(:_id)
        WorkflowServer::Models::Event.where(:status.in => [:error, :timeout], :workflow_id.in => ids).map(&:workflow).uniq
      end

      get '/paused_workflows' do
        current_user.workflows.where(status: :pause)
      end

      desc 'returns workflows that have > 0 open decisions and 0 executing decisions'
      get '/stuck_workflows' do
        ids = current_user.workflows.pluck(:_id)
        WorkflowServer::Models::Decision.where(status: :open, :workflow_id.in => ids).find_all {|decision| decision.workflow.decisions.where(status: :executing).none? }.map(&:workflow).uniq
      end

      desc 'returns workflows that have more than one decision executing simultaneously'
      get '/multiple_executing_decisions' do
        ids = current_user.workflows.pluck(:_id)
        workflow_ids = group_by_and_having(WorkflowServer::Models::Event.where(:status.nin => [:open, :complete], :workflow_id.in => ids ).type(WorkflowServer::Models::Decision).selector, 'workflow_id', 1)

        current_user.workflows.where(:id.in => workflow_ids)
      end

      desc 'returns workflows that are in an inconsistent state'
      get '/inconsistent_workflows' do
        ids = current_user.workflows.pluck(:_id)
        objects = WorkflowServer::Models::Event.where(:workflow_id.in => ids, :_type.in => [ WorkflowServer::Models::Timer.to_s, WorkflowServer::Models::Signal.to_s ]).pluck(:_id)
        duplicate_objects = group_by_and_having(WorkflowServer::Models::Event.where(:parent_id.in => objects).type(WorkflowServer::Models::Decision).selector, 'parent_id', 1)
        WorkflowServer::Models::Event.where(:id.in => duplicate_objects).map(&:workflow).uniq
      end

    end
  end
end

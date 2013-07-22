require 'grape'

module Api
  class Workflow < Grape::API
    include WorkflowServer::Logger
    extend ServiceDiscovery::Description::Dsl
    ServiceDiscovery::Description.disable! if WorkflowServer::Config.environment == :production

    # formatter :camel_json, Api::CamelJsonFormatter
    # content_type :camel_json, 'application/json'
    # format :camel_json

    format :json

    before do
      ::WorkflowServer::Helper::HashKeyTransformations.underscore_keys(params)
    end

    rescue_from :all do |e|
      Api::Workflow.error({ error: e, backtrace: e.backtrace })
      Squash::Ruby.notify e
      Rack::Response.new({error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventNotFound do |e|
      Api::Workflow.info(e)
      Squash::Ruby.notify e
      Rack::Response.new({error: e.message }.to_json, 404, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventComplete, WorkflowServer::InvalidParameters, WorkflowServer::InvalidEventStatus, WorkflowServer::InvalidOperation, WorkflowServer::InvalidDecisionSelection, Grape::Exceptions::Validation do |e|
      Api::Workflow.info(e)
      Squash::Ruby.notify e
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

    def self.namespace_desc(description)
      @namespace_description = { namespace_description: description }
    end

    SERVICE_DISCOVERY_RESPONSE_CREATOR = Proc.new { |model, response_object, specific_fields = nil|
      raise "model doesn't respond to field_hash" unless model.respond_to?(:field_hash)
      field_hash = model.field_hash

      field_hash.each_pair do |field, data|
        next if specific_fields.is_a?(Array) && !specific_fields.include?(field.to_sym)
        options = {}
        options[:description] = data[:label] if data[:label]
        case data[:type].to_s
        when "Integer"
          response_object.integer field, options
        when "Float", "BigDecimal"
          response_object.number field, options
        when "Array"
          response_object.array(field, options) {}
        when "Hash"
          response_object.object(field, options) {}
        when "Symbol", "Time", "Object"
          response_object.string field, options
        else
          response_object.string field, options
        end
      end
    }

    resource 'workflows' do
      desc "Creates a new workflow. If the workflow with the given parameter already exists, returns the existing workflow.", {
        action_descriptor: action_description(:create) do |create|
          create.parameters do |parameters|
            fields = WorkflowServer::Models::Workflow.fields
            parameters.string :workflow_type, description: fields["workflow_type"].label, required: true, location: 'body'
            parameters.object :subject, description: fields["subject"].label, required: true, location: 'body' do
            end
            parameters.string :decider, description: fields["decider"].label, required: true, location: 'body'
            parameters.string :name, description: "Name of the workflow", required: true, location: 'body'
          end
          create.response do |workflow|
            SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
          end
        end
      }
      post "/" do
        params[:user] = current_user
        wf = WorkflowServer.find_or_create_workflow(params)

        if wf.valid?
          wf
        else
          raise WorkflowServer::InvalidParameters, wf.errors.to_hash
        end
      end

      desc "Use this endpoint to backfill existing workflows to backbeat. Schedule timers for things that are supposed to go off in future.", {
        action_descriptor: action_description(:backfill_timer) do |backfill|
          backfill.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            parameters.string :name, description: 'the name for the timer', required: true, location: 'url'
            parameters.string :run_at, description: 'The time when this timer should go off. If in past, the timer will fire immediately.', required: true, location: 'body'
          end
        end
      }
      params do
        requires :run_at, type: String, desc: 'Timers need a run_at parameter'
      end
      put "/:id/backfill/timer/:name" do
        workflow = find_workflow(params[:id])
        WorkflowServer::Models::Timer.create!(name: params[:name], workflow: workflow, fires_at: params[:run_at], user: current_user).start
        { success: true }
      end

      desc "Use this endpoint to backfill existing workflows to backbeat. Add historical decisions that were completed successfully in the past.", {
        action_descriptor: action_description(:backfill_decision) do |backfill|
          backfill.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            parameters.string :name, description: 'the name for the decision', required: true, location: 'url'
          end
        end
      }
      put "/:id/backfill/decision/:name" do
        workflow = find_workflow(params[:id])
        signal = WorkflowServer::Models::Signal.create!(name: params[:name], workflow: workflow, status: :complete, user: current_user)
        decision = WorkflowServer::Models::Decision.create!(name: params[:name], workflow: workflow, status: :complete, parent: signal, user: current_user)
        { success: true }
      end

      desc "Get workflows filtered by workflow_type, decider, subject and the workflow name.", {
        action_descriptor: action_description(:get_workflows) do |get_workflows|
          get_workflows.parameters do |parameters|
            fields = WorkflowServer::Models::Workflow.fields
            parameters.string :workflow_type, description: fields["workflow_type"].label, required: false, location: 'body'
            parameters.object :subject, description: fields["subject"].label, required: false, location: 'body' do
            end
            parameters.string :decider, description: fields["decider"].label, required: false, location: 'body'
            parameters.string :name, description: "Name for the workflow", required: false, location: 'body'
          end
          get_workflows.response do |response|
            response.array(:workflows) do |workflows|
              workflows.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      put "/" do
        query = {}
        [:workflow_type, :decider, :subject].each do |query_param|
          if params.include?(query_param)
            query[query_param] = params[query_param]
          end
        end
        current_user.workflows.where(query).map {|wf| wf }
      end

      desc "Get workflow identified by the id.", {
        action_descriptor: action_description(:get_workflow) do |get_workflow|
          get_workflow.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          get_workflow.response do |workflow|
            SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
          end
        end
      }
      get "/:id" do
        find_workflow(params[:id])
      end

      {
        flags: WorkflowServer::Models::Flag,
        signals: WorkflowServer::Models::Signal,
        decisions: WorkflowServer::Models::Decision,
        activities: WorkflowServer::Models::Activity,
        timers: WorkflowServer::Models::Timer,
        events: WorkflowServer::Models::Event
      }.each_pair do |event_type, model|
        desc "Get all the #{event_type} on a workflow.", {
          action_descriptor: action_description(("get_" + event_type.to_s).to_sym) do |event|
            event.parameters do |parameters|
              parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            end
            event.response do |response|
              response.array(event_type) do |event_object|
                event_object.object do |object|
                  SERVICE_DISCOVERY_RESPONSE_CREATOR.call(model, object)
                end
              end
            end
          end
        }
        get "/:id/#{event_type}" do
          wf = find_workflow(params[:id])
          wf.__send__(event_type)
        end
      end

      desc "Get the workflow tree as a hash.", {
        # TODO - figure out how this can be made more generic
        action_descriptor: action_description(:get_workflow_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          tree.response do |response|
            SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, response, [:id, :type, :name, :status])
            response.array :children do |children|
              children.object do |child|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, child, [:id, :type, :name, :status])
              end
            end
          end
        end
      }
      get "/:id/tree" do
        wf = find_workflow(params[:id])
        wf.tree
      end

      desc "Get the workflow tree in a pretty print color encoded string format.", {
        action_descriptor: action_description(:print_workflow_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          tree.response do |response|
            response.string :print, description: "the workflow tree in a color coded string format."
          end
        end
      }
      get "/:id/tree/print" do
        begin
          identity_map_enabled = Mongoid.identity_map_enabled
          Mongoid.identity_map_enabled = true
          wf = find_workflow(params[:id])
          # load the child relation for each event into memory
          WorkflowServer::Models::Event.where(workflow_id: wf.id).includes(:children).flatten;1
          {print: wf.tree_to_s}
        ensure
          Mongoid.identity_map_enabled = identity_map_enabled
        end
      end

      desc "Send a signal to the workflow.", {
        action_descriptor: action_description(:signal_workflow) do |signal|
          fields = WorkflowServer::Models::Signal.fields
          signal.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
            parameters.string :name, description: 'the signal name', required: true, location: 'url'
            parameters.object :options, description: 'the options for the signal', required: false, location: 'body' do |options|
              options.object :client_data, description: fields['client_data'].label, required: false, location: 'body' do
              end
              options.object :client_metadata, description: fields['client_metadata'].label, required: false, location: 'body' do
              end
            end
          end
          signal.response do |response|
            SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Signal, response)
          end
        end
      }
      params do
        optional :options, type: Hash
      end
      post "/:id/signal/:name" do
        wf = find_workflow(params[:id])
        options = params[:options] || {}
        client_data = options[:client_data] || {}
        client_metadata = options[:client_metadata] || {}
        signal = wf.signal(params[:name], client_data: client_data, client_metadata: client_metadata)
        signal
      end

      desc "Pause an open workflow.", {
        action_descriptor: action_description(:pause_workflow) do |pause|
          pause.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
        end
      }
      put "/:id/pause" do
        wf = find_workflow(params[:id])
        wf.pause
        {success: true}
      end

      desc "Resume a paused workflow.", {
        action_descriptor: action_description(:resume_workflow) do |resume|
          resume.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
        end
      }
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
    EventSpecification = Proc.new do |full_url = true|
      desc "Get the event identified by the id.", {
        action_descriptor: action_description(:get_event) do |get_event|
          get_event.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          get_event.response do |event|
            SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, event)
          end
        end
      }
      get "/:id" do
        find_event(params)
      end

      desc "Restart a failed activity or decision.", {
        action_descriptor: action_description(:restart_event) do |restart_event|
          restart_event.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
        end
      }
      put "/:id/restart" do
        e = find_event(params)
        e.restart
        {success: true}
      end

      # TODO - make a more generic endpoint to return the history
      desc "Get all the decisions that have occurred in the past based off this decision", {
        action_descriptor: action_description(:history_decisions) do |history_decisions|
          history_decisions.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          history_decisions.response do |response|
            response.array(:decisions) do |event_object|
              event_object.object do |object|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Decision, object)
              end
            end
          end
        end
      }
      get "/:id/history_decisions" do
        event = find_event(params)
        event.past_decisions.where(:inactive.ne => true)
      end

      desc "Get the event tree as a hash.", {
        action_descriptor: action_description(:get_event_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          tree.response do |response|
            SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, response, [:id, :type, :name, :status])
            response.array :children do |children|
              children.object do |child|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Event, child, [:id, :type, :name, :status])
              end
            end
          end
        end
      }
      get "/:id/tree" do
        e = find_event(params)
        e.tree
      end

      desc "Get the event tree in a pretty print color encoded string format.", {
        action_descriptor: action_description(:print_event_tree) do |tree|
          tree.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the event id', required: true, location: 'url'
          end
          tree.response do |response|
            response.string :print, description: "the event tree in a color coded string format."
          end
        end
      }
      get "/:id/tree/print" do
        e = find_event(params)
        {print: e.tree_to_s}
      end

      desc "Add new decisions to an event.", {
        action_descriptor: action_description(:decisions) do |decisions|
          decisions.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity or decision id', required: true, location: 'url'
          end
        end
      }
      post "/:id/decisions" do
        raise WorkflowServer::InvalidParameters, "args parameter is invalid" if params[:args] && !params[:args].is_a?(Hash)
        raise WorkflowServer::InvalidParameters, "args must include a 'decisions' parameter" if params[:args][:decisions].nil? || params[:args][:decisions].empty?
        event = find_event(params)
        event.add_decisions(params[:args][:decisions])
        {success: true}
      end

      desc "Update the status on an event (use this endpoint for deciding, deciding_complete, completed, errored).", {
        action_descriptor: action_description(:change_status) do |change_status|
          change_status.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity or decision id', required: true, location: 'url'
          end
        end
      }
      put "/:id/status/:new_status" do
        raise WorkflowServer::InvalidParameters, "args parameter is invalid" if params[:args] && !params[:args].is_a?(Hash)
        event = find_event(params)
        event.change_status(params[:new_status], params[:args] || {})
        {success: true}
      end

      desc "Run a nested activity from inside an activity.", {
        action_descriptor: action_description(:run_activity) do |activity|
          activity.parameters do |parameters|
            parameters.string :workflow_id, description: 'the workflow id', required: true, location: 'url' if full_url
            parameters.string :id, description: 'the activity id', required: true, location: 'url'
          end
          activity.parameters do |parameters|
            parameters.object(:sub_activity, description: "Define the nested activity.", location: 'body') do |sub_activity|
              SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Activity, sub_activity, [:name, :client_data, :mode, :always, :retry, :retry_interval, :time_out])
            end
          end
        end
      }
      params do
        requires :sub_activity, type: Hash, desc: 'sub activity param cannot be empty'
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
      EventSpecification.call(false)
    end

    namespace 'debug' do

      desc 'returns workflows that have something in error or timeout state', {
        action_descriptor: action_description(:get_error_workflows, deprecated: true) do |error_workflows|
          error_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          error_workflows.response do |response|
            response.array(:error_workflows) do |error_workflow|
              error_workflow.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/error_workflows' do
        workflow_ids = WorkflowServer::Models::Event.where(:status.in => [:error, :timeout], user: current_user).pluck(:workflow_id).uniq
        WorkflowServer::Models::Workflow.where(:_id.in => workflow_ids, :status.ne => :pause)
      end

      desc 'returns paused workflows', {
        action_descriptor: action_description(:get_paused_workflows, deprecated: true) do |paused_workflows|
          paused_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          paused_workflows.response do |response|
            response.array(:paused_workflows) do |paused_workflow|
              paused_workflow.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/paused_workflows' do
        current_user.workflows.where(status: :pause)
      end

      desc 'returns workflows that have > 0 open decisions and 0 executing decisions', {
        action_descriptor: action_description(:get_stuck_workflows, deprecated: true) do |stuck_workflows|
          stuck_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          stuck_workflows.response do |response|
            response.array(:paused_workflows) do |stuck_workflow|
              stuck_workflow.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/stuck_workflows' do
        WorkflowServer::Models::Decision.where(status: :open, user: current_user).find_all {|decision| decision.workflow.decisions.where(:status.in => [:error, :executing, :restarting, :sent_to_client]).none? }.map(&:workflow).uniq
      end

      desc 'returns workflows with events executing for over 24 hours', {
        action_descriptor: action_description(:long_running_events, deprecated: true) do |long_running_events|
          long_running_events.response do |response|
            response.array(:long_running_events) do |stuck_workflow|
              stuck_workflow.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/long_running_events' do
        long_running_events = WorkflowServer::Models::Event.where(:status.in => [:executing, :restarting, :sent_to_client, :retrying], user: current_user).and(:_type.nin => [WorkflowServer::Models::Workflow]).and(:updated_at.lt => 24.hours.ago)
        long_running_events.map(&:workflow).find_all {|wf| !wf.paused? && wf.status != :complete && wf.events.where(status: :error).empty? }.uniq
      end

      desc 'returns workflows that have more than one decision executing simultaneously', {
        action_descriptor: action_description(:get_workflows_with_multiple_executing_decisions, deprecated: true) do |workflows_with_multiple_executing_decisions|
          workflows_with_multiple_executing_decisions.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          workflows_with_multiple_executing_decisions.response do |response|
            response.array(:workflow) do |workflow_with_multiple_executing_decision|
              workflow_with_multiple_executing_decision.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/multiple_executing_decisions' do
        workflow_ids = group_by_and_having(WorkflowServer::Models::Event.where(:status.nin => [:open, :complete, :resolved, :error], user: current_user ).type(WorkflowServer::Models::Decision).selector, 'workflow_id', 1)
        current_user.workflows.where(:id.in => workflow_ids)
      end

      desc 'returns workflows that are in an inconsistent state', {
        action_descriptor: action_description(:get_inconsistent_workflows, deprecated: true) do |inconsistent_workflows|
          inconsistent_workflows.parameters do |parameters|
            parameters.string :id, description: 'the workflow id', required: true, location: 'url'
          end
          inconsistent_workflows.response do |response|
            response.array(:inconsistent_workflow) do |inconsistent_workflow|
              inconsistent_workflow.object do |workflow|
                SERVICE_DISCOVERY_RESPONSE_CREATOR.call(WorkflowServer::Models::Workflow, workflow)
              end
            end
          end
        end
      }
      get '/inconsistent_workflows' do
        parents_with_multiple_decisions = group_by_and_having(WorkflowServer::Models::Event.where(_type: WorkflowServer::Models::Decision).selector, 'parent_id', 1)
        inconsistent_workflow_ids = WorkflowServer::Models::Event.where(user: current_user, :_id.in => parents_with_multiple_decisions, :_type.in => [ WorkflowServer::Models::Timer, WorkflowServer::Models::Signal ]).pluck(:workflow_id).uniq
        WorkflowServer::Models::Workflow.where(:id.in => inconsistent_workflow_ids)
      end

    end
  end
end

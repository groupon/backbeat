module Api
  module ApiHelpers

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

    def workflow_status(workflow)
      workflow_status = workflow.status

      errored = workflow.events.and(status: :error).exists?
      if errored
        workflow_status = :error
      else
        executing = workflow.events.and(status: :executing).exists?
        workflow_status = :executing if executing
      end
      workflow_status
    end
  end
end

class V2::Server
  MarkChildrenReady = :mark_children_ready
  ChildrenReady = :children_ready
  ScheduleNextNode = :schedule_next_node
  StartNode = :start_node
  ClientComplete = :client_complete
  ClientProcessing = :client_processing
  ClientError = :client_error
  ClientResolved = :client_resolved
  ProcessChildren = :process_children
  NodeComplete = :node_complete




  def self.create_workflow(params, user)
    value = { workflow_type: params['workflow_type'],
              subject: params['subject'],
              decider: params['decider'],
              initial_signal: params['sinitial_signal'] || :start,
              user_id: user.id}
    unless workflow = V2::Workflow.where(subject:  params['subject'].to_json).first
      workflow = V2::Workflow.create!(value)
    end

    workflow
  end

  def self.add_node(user, workflow, params, parent_node)
   value = { mode: params['mode'].to_sym,
    current_server_status: :pending,
    current_client_status: :pending,
    name: params['name'],
    fires_at: params['fires_at'] || Time.now - 1.second, #not a huge fan of this but would like it to fire imediatly
    parent: parent_node,
    workflow_id: workflow.id,
    user_id: user.id}
    ap value
    node = V2::Node.create!(value)
    V2::ClientNodeDetail.create!(node: node,
                                 metadata: params[:options][:client_metadata] || {},
                                 data: params[:options][:client_data] || {})

    V2::NodeDetail.create!(node: node,
                           legacy_type: params['legacy_type'])
    node
  end

  def self.fire_event(event, workflow, node)
    case event
      when MarkChildrenReady
        V2::Processors.mark_children_ready(workflow, node)
      when ChildrenReady
        V2::Processors.node_ready(workflow, node)
      when ScheduleNextNode
        V2::Processors.schedule_next_node(workflow, node)
      when StartNode
        V2::Processors.start_node(workflow, node)
      when ClientProcessing
        V2::Processors.client_processing(workflow, node)
      when ClientComplete
        V2::Processors.client_complete(workflow, node)
      when ProcessChildren
        V2::Processors.schedule_next_node(workflow, node)
      when NodeComplete
        V2::Processors.node_complete(workflow, node)
    end
  end
end



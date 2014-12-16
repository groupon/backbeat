class V2::Server
  MarkChildrenReady = :mark_children_ready
  ChildrenReady = :children_ready
  ScheduleNextNode = :schedule_next_node
  StartNode = :start_node



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
   value = { mode: :blocking,
    current_server_status: :pending,
    current_client_status: :pending,
    name: params['name'],
    fires_at: params['fires_at'] || Time.now - 1.second, #not a huge fan of this but would like it to fire imediatly
    parent: parent_node,
    workflow_id: workflow.id,
    user_id: user.id}

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
    end
  end
end



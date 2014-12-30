class V2::Processors
  include WorkflowServer::Logger

  def self.mark_children_ready(workflow, node)
    info(mark_children_ready: {workflow: workflow, node:  node})
    node.children.each do |child_node|
      child_node.update_attributes!(current_server_status: :ready, current_client_status: :ready)
    end
    V2::Server::fire_event(V2::Server::ChildrenReady, workflow, node)
  end

  def self.node_ready(workflow, node)
    info(node_ready: {workflow: workflow, node:  node})

    if node.all_children_ready?
      V2::Server::fire_event(V2::Server::ScheduleNextNode, workflow, node)
    end
  end

  def self.schedule_next_node(workflow, node)
    info(schedule_next_node: {workflow: workflow, node:  node})
    if node.all_children_complete?
      if !node.is_a?(V2::Workflow)
        return V2::Server::fire_event(V2::Server::NodeComplete, workflow, node)
      else
        return
      end
    else
      node.not_complete_children.find_each do |child_node|
        if child_node.current_server_status.ready?
          child_node.update_attributes!(current_server_status: :started)
          return V2::Server::fire_event(V2::Server::StartNode, workflow, child_node)
        else
          return
        end
      end
    end
  end

  def self.start_node(workflow, node)
    info(start_node: {workflow: workflow, node:  node})
    return if node.current_server_status.ready?

    if node.node_detail.legacy_type == 'signal'
      dec = node.attributes.merge(decider: node.workflow.decider, subject: node.workflow.subject)
      WorkflowServer::Client.make_decision(dec, node.user)
    else
      activity = node.attributes.merge(client_data: node.client_node_detail.data)
      WorkflowServer::Client.perform_activity(activity, node.user)
    end
   node.update_attributes!(current_server_status: :sent_to_client,
                                   current_client_status: :received) 
  end

  def self.client_processing(workflow, node)
    info(client_processing: {workflow: workflow, node:  node})
    node.update_attributes!(current_client_status: :processing)
  end

  def self.client_complete(workflow, node)
    info(client_complete: {workflow: workflow, node:  node})
    node.update_attributes!(current_client_status: :complete, current_server_status: :processing_children )
    V2::Server.fire_event(V2::Server::MarkChildrenReady, workflow, node)
  end

   def self.node_complete(workflow, node)
    info(node_complete: {workflow: workflow, node:  node})
    node.update_attributes!(current_server_status: :complete )
    V2::Server.fire_event(V2::Server::ScheduleNextNode, workflow, node.current_parent)
  end


end

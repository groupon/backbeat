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
      return V2::Server::fire_event(V2::Server::NodeComplete, workflow, node)      else
      node.not_complete_children.find_each do |child_node|
        if child_node.current_server_status.ready?
          child_node.update_attributes!(current_server_status: :started)

          V2::Server::fire_event(V2::Server::StartNode, workflow, child_node)
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
      WorkflowServer::Client.make_decision(node, node.user)
    else
      WorkflowServer::Client.perform_activity(node, node.user)
    end
    node.update_attributes!(current_server_status: :sent_to_client,
                                   current_client_status: :processing)
  end
end

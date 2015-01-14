class V2::Processors
  include WorkflowServer::Logger

  def self.mark_children_ready(node)
    info(mark_children_ready: {node:  node})
    node.children.each do |child_node|
      child_node.update_attributes!(current_server_status: :ready, current_client_status: :ready)
    end
    V2::Server::fire_event(V2::Server::ChildrenReady,  node)
  end

  def self.children_ready(node)
    info(node_ready: { node:  node})

    if node.all_children_ready?
      V2::Server::fire_event(V2::Server::ScheduleNextNode,  node)
    end
  end

  def self.schedule_next_node( node)
    info(schedule_next_node: {node:  node})
    if node.all_children_complete?
      if !node.is_a?(V2::Workflow)
        return V2::Server::fire_event(V2::Server::NodeComplete,  node)
      else
        return
      end
    else
      node.not_complete_children.find_each do |child_node|
        if child_node.current_server_status.ready?
          child_node.update_attributes!(current_server_status: :started)
          return V2::Server::fire_event(V2::Server::StartNode,  child_node)
        else
          return
        end
      end
    end
  end

  DecisionWhiteList = [:decider, :subject, :id, :name, :parent_id, :user_id]
  ActivityWhiteList = [:id, :mode, :name, :name, :parent_id, :workflow_id, :user_id, :client_data]
  def self.start_node(node)
    info(start_node: { node:  node})
    return if node.current_server_status.ready?

    if node.node_detail.legacy_type == 'signal'
      dec = node.attributes.merge(decider: node.workflow.decider, subject: node.workflow.subject)
      WorkflowServer::Client.make_decision(dec.keep_if {|k,_| DecisionWhiteList.include? k.to_sym }, node.user)
    else
      activity = node.attributes.merge(client_data: node.client_node_detail.data)
      WorkflowServer::Client.perform_activity(activity.keep_if {|k,_| ActivityWhiteList.include? k.to_sym }, node.user)
    end
    node.update_attributes!(current_server_status: :sent_to_client,
                            current_client_status: :received)
  end

  def self.client_processing(node)
    info(client_processing: {node: node})
    node.update_attributes!(current_client_status: :processing)
  end

  def self.client_complete(node)
    info(client_complete: {node:  node})
    node.update_attributes!(current_client_status: :complete, current_server_status: :processing_children)
    V2::Server.fire_event(V2::Server::MarkChildrenReady, node)
  end

  def self.node_complete(node)
    info(node_complete: {node: node})
    node.update_attributes!(current_server_status: :complete)
    V2::Server.fire_event(V2::Server::ScheduleNextNode, node.current_parent)
  end

  def self.client_error(node)
    info(client_error: {node: node})
    node.update_attributes!(current_server_status: :errored, current_client_status: :errored)
    V2::Server.fire_event(V2::Server::RetryNode, node)
  end

  def self.retry_node(node)
    info(retry_node: {node: node})
    node_detail = node.node_detail
    retries_remaining = node_detail.retry_times_remaining

    if retries_remaining > 0
      node_detail.update_attributes!(retry_times_remaining: retries_remaining-1)
      node.update_attributes!(current_server_status: :retrying)
      V2::Server.fire_event(V2::Server::StartNode, node)
    else
      update_attributes!(current_server_status: :errored, current_client_status: :errored)
    end
  end
end

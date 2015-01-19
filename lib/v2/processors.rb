module V2
  class Processors

    # we can have this method or perform a no op when moving to ready if already past ready
    def self.mark_signal_ready(node)
      Logger.info(mark_signal_ready: {node: node})

      node.update_status(current_server_status: :ready, current_client_status: :ready)
      Server::fire_event(Server::ScheduleNextNode, node.workflow)
    end

    def self.mark_children_ready(node)
      Logger.info(mark_children_ready: {node: node})
      node.children.each do |child_node|
        child_node.update_status(current_server_status: :ready, current_client_status: :ready)
      end
      Server::fire_event(Server::ChildrenReady, node)
    end

    def self.children_ready(node)
      Logger.info(node_ready: { node: node })

      if node.all_children_ready?
        Server::fire_event(Server::ScheduleNextNode, node)
      end
    end

    def self.schedule_next_node(node)
      Logger.info(schedule_next_node: {node: node})
      if node.all_children_complete?
        if !node.is_a?(Workflow)
          Server::fire_event(Server::NodeComplete, node)
        end
      else
        node.ready_children.each do |child_node|
          child_node.update_status(current_server_status: :started)
          Server::fire_event(Server::StartNode, child_node)
          break if child_node.blocking?
        end
      end
    end

    DECISION_WHITE_LIST = [:decider, :subject, :id, :name, :parent_id, :user_id]
    ACTIVITY_WHITE_LIST = [:id, :mode, :name, :name, :parent_id, :workflow_id, :user_id, :client_data]

    def self.start_node(node)
      Logger.info(start_node: { node: node})
      return if node.current_server_status.ready?

      if node.legacy_type == 'signal'
        decision = node.attributes.merge(decider: node.workflow.decider, subject: node.workflow.subject)
        WorkflowServer::Client.make_decision(decision.keep_if {|k,_| DECISION_WHITE_LIST.include? k.to_sym }, node.user)
      else
        activity = node.attributes.merge(client_data: node.client_node_detail.data)
        WorkflowServer::Client.perform_activity(activity.keep_if {|k,_| ACTIVITY_WHITE_LIST.include? k.to_sym }, node.user)
      end
      node.update_status(current_server_status: :sent_to_client, current_client_status: :received)
    end

    def self.client_processing(node)
      Logger.info(client_processing: {node: node})
      node.update_status(current_client_status: :processing)
    end

    def self.client_complete(node)
      Logger.info(client_complete: {node: node})
      node.update_status(current_client_status: :complete, current_server_status: :processing_children)
      Server.fire_event(Server::MarkChildrenReady, node)
    end

    def self.node_complete(node)
      Logger.info(node_complete: {node: node})
      node.update_status(current_server_status: :complete)
      Server.fire_event(Server::ScheduleNextNode, node.current_parent)
    end

    def self.client_error(node, args)
      Logger.info(client_error: {node: node})
      node.update_status(current_server_status: :errored, current_client_status: :errored)
      if node.retries_remaining > 0
        node.mark_retried!
        Server.fire_event(Server::RetryNodeWithBackoff, node)
      else
        Client.notify_of(node, "error", args[:error_mesage])
      end
    end

    def self.retry_node(node)
      Logger.info(retry_node: {node: node})
      node.update_status(current_server_status: :retrying)
      Server.fire_event(Server::StartNode, node)
    end
  end
end
module V2
  class Processors

    def self.mark_children_ready(node)
      Instrument.instrument(node, :mark_children_ready) do
        node.children.each do |child_node|
          StateManager.call(child_node,
            current_server_status: :ready,
            current_client_status: :ready
          )
        end
        Server::fire_event(Server::ChildrenReady, node)
      end
    end

    def self.children_ready(node)
      Instrument.instrument(node, :children_ready) do
        Server::fire_event(Server::ScheduleNextNode, node) if node.all_children_ready?
      end
    end

    def self.schedule_next_node(node)
      Instrument.instrument(node, :schedule_next_node) do
        node.not_complete_children.each do |child_node|
          if child_node.current_server_status.ready?
            Server::fire_event(Server::StartNode, child_node)
            StateManager.call(child_node, current_server_status: :started)
          end
          break if child_node.blocking?
        end
        Server.fire_event(Server::NodeComplete, node) if node.all_children_complete?
      end
    end

    def self.start_node(node)
      Instrument.instrument(node, :start_node) do
        node.with_lock do
          return if node.already_performed?
          StateManager.call(
            node,
            current_server_status: :sent_to_client,
            current_client_status: :received
          )
        end

        if node.perform_client_action?
          Client.perform_action(node)
        else
          Server.fire_event(Server::ClientComplete, node)
        end
      end
    end

    def self.client_processing(node)
      Instrument.instrument(node, :client_processing) do
        Logger.info(client_processing: { node: node })
        StateManager.call(node, current_client_status: :processing)
      end
    end

    def self.client_complete(node)
      Instrument.instrument(node, :client_complete) do
        Logger.info(client_complete: { node: node })
        StateManager.call(node,
          current_client_status: :complete,
          current_server_status: :processing_children
        )
        Server.fire_event(Server::MarkChildrenReady, node)
      end
    end

    def self.node_complete(node)
      Instrument.instrument(node, :node_complete) do
        if node.parent
          Logger.info(node_complete: { node: node })
          StateManager.call(node, current_server_status: :complete)
          Server.fire_event(Server::ScheduleNextNode, node.parent)
        end
      end
    end

    def self.client_error(node, args)
      Instrument.instrument(node, :client_error) do
        StateManager.call(node,
          current_server_status: :errored,
          current_client_status: :errored
        )
        if node.retries_remaining > 0
          node.mark_retried!
          Server.fire_event(Server::RetryNodeWithBackoff, node)
        else
          Client.notify_of(node, "error", args[:error_message])
        end
      end
    end

    def self.retry_node(node)
      Instrument.instrument(node, :retry_node) do
        StateManager.call(node, current_server_status: :retrying)
        Server.fire_event(Server::StartNode, node)
      end
    end
  end
end

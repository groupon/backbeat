module V2
  module Events
    class MarkChildrenReady
      def self.call(node)
        node.active_children.each do |child_node|
          StateManager.transition(
            child_node,
            current_server_status: :ready,
            current_client_status: :ready
          )
        end
        Server.fire_event(ScheduleNextNode, node)
      end
    end

    class ScheduleNextNode
      def self.call(node)
        node.not_complete_children.each do |child_node|
          transitioned = false

          begin
            child_node.with_lock("FOR UPDATE NOWAIT") do
              if child_node.current_server_status.ready?
                StateManager.transition(child_node, current_server_status: :started)
                transitioned = true
              end
            end
          rescue ActiveRecord::StatementInvalid
            # Could not gain lock on child_node. Another worker is in schedule_next_node already for this workflow
            # We only need one schedule_next_node to keep the tree moving so lets get out of here
            return
          end

          if transitioned
            StateManager.with_rollback(child_node, current_server_status: :ready) do
              Server.fire_event(StartNode, child_node)
            end
          end

          break if child_node.blocking?
        end
        Server.fire_event(NodeComplete, node) if node.all_children_complete?
      end
    end

    class StartNode
      def self.call(node)
        if node.paused?
          StateManager.transition(node, current_server_status: :paused)
          return
        end
        StateManager.transition(node,
          current_server_status: :sent_to_client,
          current_client_status: :received
        )
        if node.perform_client_action?
          Client.perform_action(node)
        else
          Server.fire_event(ClientComplete, node)
        end
      rescue WorkflowServer::HttpError => e
        node.client_node_detail.update_attributes(result: { error: e, message: e.message })
        Server.fire_event(ClientError, node)
      end
    end

    class ClientProcessing
      def self.call(node)
        StateManager.transition(node, current_client_status: :processing)
      end
    end

    class ClientComplete
      def self.call(node)
        StateManager.with_rollback(node) do |state|
          state.transition(current_client_status: :complete, current_server_status: :processing_children)
          Server.fire_event(MarkChildrenReady, node)
        end
      end
    end

    class NodeComplete
      def self.call(node)
        if node.parent
          StateManager.transition(node, current_server_status: :complete)
          Server.fire_event(ScheduleNextNode, node.parent)
        end
      end
    end

    class ServerError
      def self.call(node)
        StateManager.transition(node, current_server_status: :errored)
        Client.notify_of(node, "error", "Server Error")
      end
    end

    class ClientError
      def self.call(node)
        StateManager.transition(node, current_client_status: :errored)
        if node.retries_remaining > 0
          node.mark_retried!
          Server.fire_event(RetryNode, node)
        else
          Client.notify_of(node, "error", "Client Errored")
        end
      end
    end

    class RetryNode
      def self.call(node)
        StateManager.transition(node, current_client_status: :ready, current_server_status: :retrying)
        StateManager.transition(node, current_server_status: :ready)
        Server.fire_event(ResetNode, node)
        Server.fire_event(ScheduleNextNode, node.parent)
      end
    end

    class DeactivatePreviousNodes
      def self.call(node)
        WorkflowTree.new(node.workflow).traverse(root: false) do |child_node|
          StateManager.transition(child_node, current_server_status: :deactivated) if child_node.seq < node.seq
        end
      end
    end

    class ResetNode
      def self.call(node)
        WorkflowTree.new(node).traverse(root: false) do |child_node|
          StateManager.transition(child_node, current_server_status: :deactivated)
        end
      end
    end
  end
end

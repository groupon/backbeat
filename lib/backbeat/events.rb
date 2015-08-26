require 'backbeat/events/event'

module Backbeat
  module Events
    class MarkChildrenReady < Event
      scheduler Schedulers::PerformEvent

      def call(node)
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

    class ScheduleNextNode < Event
      scheduler Schedulers::ScheduleNow

      def call(node)
        node.not_complete_children.each do |child_node|
          if child_node.current_server_status.ready?
            StateManager.transition(child_node, current_server_status: :started)
            StateManager.new(child_node).with_rollback(current_server_status: :ready) do
              Server.fire_event(StartNode, child_node)
            end
          end
          break if child_node.blocking?
        end

        Server.fire_event(NodeComplete, node) if node.all_children_complete? && node.link_complete?
      rescue StaleStatusChange => e
        Logger.info(message: "Aborting concurrent scheduling process", node: node.id, error: e.message)
      end
    end

    class StartNode < Event
      scheduler Schedulers::ScheduleAt

      def call(node)
        if node.paused?
          StateManager.transition(node, current_server_status: :paused)
          return
        end
        node.touch!
        StateManager.transition(node,
          current_server_status: :sent_to_client,
          current_client_status: :received
        )
        if node.perform_client_action?
          Client.perform_action(node)
        else
          Server.fire_event(ClientComplete, node)
        end
      rescue HttpError => e
        response = { error: { message: e.message } }
        Server.fire_event(ClientError.new(response), node)
      end
    end

    class ClientProcessing < Event
      include ResponseHandler
      scheduler Schedulers::PerformEvent

      def call(node)
        StateManager.transition(node, current_client_status: :processing)
      end
    end

    class ClientComplete < Event
      include ResponseHandler
      scheduler Schedulers::PerformEvent

      def call(node)
        StateManager.new(node, response).with_rollback do |state|
          state.transition(current_client_status: :complete, current_server_status: :processing_children)
          Server.fire_event(MarkChildrenReady, node)
        end
      end
    end

    class NodeComplete < Event
      scheduler Schedulers::PerformEvent

      def call(node)
        if node.parent
          StateManager.transition(node, current_server_status: :complete)
          node.nodes_to_notify.each{|node_to_notify| Server.fire_event(ScheduleNextNode, node_to_notify) }
        end
      end
    end

    class ServerError < Event
      include ResponseHandler
      scheduler Schedulers::PerformEvent

      def call(node)
        StateManager.new(node, response).transition(current_server_status: :errored)
        Client.notify_of(node, "Server Error", response[:error])
      end
    end

    class ClientError < Event
      include ResponseHandler
      scheduler Schedulers::PerformEvent

      def call(node)
        StateManager.new(node, response).transition(current_client_status: :errored)
        if node.retries_remaining > 0
          node.mark_retried!
          Server.fire_event(RetryNode, node)
        else
          Client.notify_of(node, "Client Error", response[:error])
        end
      end
    end

    class RetryNode < Event
      scheduler Schedulers::ScheduleRetry

      def call(node)
        StateManager.transition(node, current_client_status: :ready, current_server_status: :retrying)
        StateManager.transition(node, current_server_status: :ready)
        Server.fire_event(ResetNode, node)
        Server.fire_event(ScheduleNextNode, node.parent)
      end
    end

    class DeactivatePreviousNodes < Event
      scheduler Schedulers::PerformEvent

      def call(node)
        WorkflowTree.new(node.workflow).traverse(root: false) do |child_node|
          StateManager.transition(child_node, current_server_status: :deactivated) if child_node.seq < node.seq
        end
      end
    end

    class ResetNode < Event
      scheduler Schedulers::PerformEvent

      def call(node)
        WorkflowTree.new(node).traverse(root: false) do |child_node|
          StateManager.transition(child_node, current_server_status: :deactivated)
        end
      end
    end
  end
end

module V2
  module Events
    class MarkChildrenReady
      def self.scheduler
        Schedulers::NowScheduler
      end

      def self.call(node)
        node.children.each do |child_node|
          StateManager.call(
            child_node,
            current_server_status: :ready,
            current_client_status: :ready
          )
        end
        Server::fire_event(ChildrenReady, node)
      end
    end

    class ChildrenReady
      def self.scheduler
        Schedulers::NowScheduler
      end

      def self.call(node)
        Server::fire_event(ScheduleNextNode, node) if node.all_children_ready?
      end
    end

    class ScheduleNextNode
      def self.scheduler
        Schedulers::AsyncScheduler
      end

      def self.call(node)
        node.not_complete_children.each do |child_node|
          child_node.with_lock do
            if child_node.current_server_status.ready?
              StateManager.call(child_node, current_server_status: :started)
              Server::fire_event(StartNode, child_node)
            end
          end
          break if child_node.blocking?
        end
        Server.fire_event(NodeComplete, node) if node.all_children_complete?
      end
    end

    class StartNode
      def self.scheduler
        Schedulers::AtScheduler
      end

      def self.call(node)
        StateManager.call(node,
          current_server_status: :sent_to_client,
          current_client_status: :received
        )

        if node.perform_client_action?
          Client.perform_action(node)
        else
          Server.fire_event(ClientComplete, node)
        end
      end
    end

    class ClientProcessing
      def self.scheduler
        Schedulers::NowScheduler
      end

      def self.call(node)
        StateManager.call(node, current_client_status: :processing)
      end
    end

    class ClientComplete
      def self.scheduler
        Schedulers::NowScheduler
      end

      def self.call(node)
        StateManager.call(
          node,
          current_client_status: :complete,
          current_server_status: :processing_children
        )
        Server.fire_event(MarkChildrenReady, node)
      end
    end

    class NodeComplete
      def self.scheduler
        Schedulers::NowScheduler
      end

      def self.call(node)
        if node.parent
          Logger.info(node_complete: { node: node })
          StateManager.call(node, current_server_status: :complete)
          Server.fire_event(ScheduleNextNode, node.parent)
        end
      end
    end

    class ClientError
      def self.scheduler
        Schedulers::NowScheduler
      end

      def self.call(node)
        StateManager.call(
          node,
          current_server_status: :errored,
          current_client_status: :errored
        )
        if node.retries_remaining > 0
          node.mark_retried!
          Server.fire_event(RetryNode, node)
        else
          Client.notify_of(node, "error", "Client Errored")
        end
      end
    end

    class RetryNode
      def self.scheduler
        Schedulers::IntervalScheduler
      end

      def self.call(node)
        StateManager.call(node, current_server_status: :retrying)
        StateManager.call(node, current_server_status: :ready)
        Server.fire_event(ScheduleNextNode, node.parent)
      end
    end
  end
end

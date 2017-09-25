# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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

        Server.fire_event(NodeComplete, node) if node.all_children_complete?
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
          Client.perform(node)
        else
          Server.fire_event(ClientComplete, node)
        end
      rescue NetworkError => e
        Kernel.sleep(Config.options[:connection_error_wait])
        if (node.reload.current_client_status != :complete)
          response = { error: { message: e.message } }
          Server.fire_event(ClientError.new(response), node)
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
          node.mark_complete!
          Server.fire_event(MarkChildrenReady, node)
        end
      end
    end

    class ClientResolved < Event
      include ResponseHandler
      scheduler Schedulers::PerformEvent

      def call(node)
        StateManager.new(node, response).transition({
          current_client_status: :resolved,
          current_server_status: :processing_children
        })
        node.mark_complete!
        Server.fire_event(MarkChildrenReady, node)
      end
    end

    class ShutdownNode < Event
      include ResponseHandler
      scheduler Schedulers::PerformEvent

      def call(node)
        StateManager.new(node, response).transition({
          current_client_status: :shutdown,
          current_server_status: :processing_children
        })
        node.mark_complete!
        if node.blocking?
          node.parent.children.each do |child|
            StateManager.transition(child, current_server_status: :deactivated) if child.seq > node.seq
          end
        end
        Server.fire_event(MarkChildrenReady, node)
      end
    end

    class NodeComplete < Event
      scheduler Schedulers::PerformEvent

      def call(node)
        if node.parent && !node.complete?
          StateManager.transition(node, current_server_status: :complete)
          unless node.fire_and_forget?
            node.nodes_to_notify.each do |node_to_notify|
              Server.fire_event(ScheduleNextNode, node_to_notify)
            end
          end
        end
      rescue StaleStatusChange => e
        Logger.info(message: "Node already complete", node: node.id, error: e.message)
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
          StateManager.transition(node, current_server_status: :retrying)
          Server.fire_event(RetryNode, node)
        else
          StateManager.transition(node, current_server_status: :retries_exhausted)
          Client.notify_of(node, "Client Error", response[:error])
        end
      end
    end

    class RetryNode < Event
      scheduler Schedulers::ScheduleRetry

      def call(node)
        StateManager.transition(node, current_client_status: :ready, current_server_status: :ready)
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

    class CancelNode < Event
      scheduler Schedulers::PerformEvent

      def call(node)
        WorkflowTree.new(node).traverse(root: true) do |child_node|
          StateManager.transition(child_node, current_server_status: :deactivated)
        end

        Server.fire_event(ScheduleNextNode, node.parent)
      end
    end
  end
end

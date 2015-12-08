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

module Backbeat
  class Presenter

    # Required interface for `present x with: XPresenter` in Grape endpoints
    def self.represent(obj, _grape_env)
      present(obj)
    end

    def self.present(obj)
      case obj
      when Array, ActiveRecord::Relation
        obj.map { |o| present(o) }
      else
        new.present(obj)
      end
    end
  end

  class WorkflowPresenter < Presenter
    def present(workflow)
      {
        id: workflow.id,
        name: workflow.name,
        subject: workflow.subject,
        decider: workflow.decider,
        userId: workflow.user_id,
        createdAt: workflow.created_at,
        updatedAt: workflow.updated_at,
        complete: workflow.complete?,
        paused: workflow.paused?,
      }
    end
  end

  class TreePresenter < Presenter
    def present(tree)
      Util.camelize(tree)
    end
  end

  class NodePresenter < Presenter
    def present(node)
      {
        id: node.id,
        mode: node.mode,
        name: node.name,
        workflowId: node.workflow_id,
        parentId: node.parent_id,
        userId: node.user_id,
        clientData: node.client_data,
        metadata: node.client_metadata,
        subject: node.subject,
        decider: node.decider,
        workflowName: node.workflow_name,
        currentServerStatus: node.current_server_status,
        currentClientStatus: node.current_client_status
      }
    end
  end

  class NotificationPresenter < Presenter
    def initialize(message = nil, error = {})
      @message = message
      @error = error
    end

    def present(node)
      {
        node: NodePresenter.present(node),
        notification: {
          name: node.name,
          message: @message
        },
        error: ErrorPresenter.present(@error)
      }
    end
  end

  class ErrorPresenter < Presenter
    def present(error)
      case error
      when InvalidClientStatusChange
        {
          errorClass: error.class.to_s,
          message: error.message,
        }.merge(Util.camelize(error.data))
      when StandardError
        {
          errorClass: error.class.to_s,
          message: error.message
        }
      when String
        { message: error }
      when Hash
        error
      else
        {}
      end
    end
  end

  class StatusPresenter < Presenter
    def present(status)
      {
        nodeId: status.node_id,
        fromStatus: status.from_status,
        toStatus: status.to_status,
        statusType: status.status_type,
        response: status.response,
        createdAt: status.created_at
      }
    end
  end
end

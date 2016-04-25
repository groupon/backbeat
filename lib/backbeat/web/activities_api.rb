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

require 'backbeat/errors'
require 'backbeat/server'
require 'backbeat/models/node'
require 'backbeat/search/activity_search'
require 'backbeat/web/versioned_api'
require 'backbeat/web/helpers/current_user_helper'

module Backbeat
  module Web
    class ActivitiesAPI < VersionedAPI

      CLIENT_EVENTS = {
        deciding: Events::ClientProcessing, # Legacy status
        processing: Events::ClientProcessing,
        deciding_complete: Events::ClientComplete, # Legacy status
        completed: Events::ClientComplete,
        errored: Events::ClientError,
        resolved: Events::ClientResolved,
        shutdown: Events::ShutdownNode,
        deactivated: Events::DeactivatePreviousNodes,
        canceled: Events::CancelNode
      }

      api do
        helpers CurrentUserHelper

        helpers do
          def find_node
            query = { user_id: current_user.id }
            query[:workflow_id] = params[:workflow_id] if params[:workflow_id]
            Node.where(query).find(params[:id])
          end

          def validate(params, param, type, message)
            value = params[param] || params.fetch(:args, {})[param]
            unless value.is_a?(type)
              raise InvalidParameters, message
            end
            value
          end
        end

        before do
          authenticate!
        end

        get "/search" do
          nodes = Search::ActivitySearch.new(params, current_user.id).result
          present nodes, with: NodePresenter
        end

        get "/:id" do
          present find_node, with: NodePresenter
        end

        get "/:id/errors" do
          errors = find_node.status_changes.where(to_status: :errored)
          present errors, with: StatusPresenter
        end

        get "/:id/response" do
          find_node.status_changes.where(status_type: :current_client_status).last.try(:response)
        end

        get "/:id/status_changes" do
          status_changes = find_node.status_changes
          present status_changes, with: StatusPresenter
        end

        put "/:id/status/:new_status" do
          node = find_node
          node.touch!
          new_status = params[:new_status].to_sym
          event_type = CLIENT_EVENTS.fetch(new_status) do
            raise UnknownStatus, "Unknown status change #{new_status}"
          end
          response = params[:response] || params[:args]
          event = response ? event_type.new(response) : event_type
          Server.fire_event(event, node)
          { success: true }
        end

        put "/:id/schedule" do
          node = find_node
          node.touch!
          Server.fire_event(Events::ScheduleNextNode, node)
        end

        put "/:id/restart" do
          node = find_node

          unless node.current_server_status == 'retries_exhausted'
            # remove any async jobs which might auto-retry running this node
            Workers::AsyncWorker.remove_job(Events::RetryNode, node)
          end

          Server.fire_event(Events::RetryNode, node, Schedulers::PerformEvent)
          { success: true }
        end

        put "/:id/reset" do
          node = find_node
          Server.fire_event(Events::ResetNode, node)
          { success: true }
        end

        post "/:id/decisions" do
          require_auth_token!
          decisions = validate(params, :decisions, Array, "Params must include a 'decisions' param")
          node = find_node
          decisions.map do |dec|
            node_to_add = dec.merge({ legacy_type: dec[:type] })
            Server.add_node(current_user, node, node_to_add).id
          end
        end
      end
    end
  end
end

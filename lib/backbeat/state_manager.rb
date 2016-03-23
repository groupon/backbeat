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
  class StateManager

    VALID_STATE_CHANGES = {
      current_client_status: {
        pending: [:ready, :errored],
        ready: [:received, :errored],
        received: [:processing, :complete, :errored],
        processing: [:complete, :errored],
        errored: [:ready, :errored, :resolved],
        complete: [:complete]
      },
      current_server_status: {
        pending: [:ready, :deactivated, :errored],
        ready: [:started, :deactivated, :errored],
        started: [:sent_to_client, :paused, :deactivated, :errored],
        sent_to_client: [:processing_children, :retrying, :retries_exhausted, :deactivated, :errored],
        processing_children: [:complete, :deactivated, :errored],
        complete: [:deactivated],
        paused: [:started, :deactivated, :errored],
        errored: [:ready, :deactivated, :errored],
        retrying: [:ready, :deactivated, :errored],
        retries_exhausted: [:ready, :deactivated, :errored, :processing_children],
        deactivated: [:deactivated]
      }
    }

    def self.transition(node, statuses = {})
      new(node).transition(statuses)
    end

    def initialize(node, response = {})
      @node = node
      @response = response
    end

    def transition(statuses)
      return if node.is_a?(Workflow)

      [:current_client_status, :current_server_status].each do |status_type|
        new_status = statuses[status_type]
        next unless new_status
        validate_status(new_status.to_sym, status_type)
      end

      update_statuses(statuses)
    end

    def with_rollback(rollback_statuses = {})
      starting_statuses = current_statuses
      yield self
    rescue InvalidStatusChange
      raise
    rescue => e
      update_statuses(starting_statuses.merge(rollback_statuses))
      raise
    end

    private

    attr_reader :node, :response

    def current_statuses
      [:current_client_status, :current_server_status].reduce({}) do |statuses, status_type|
        statuses[status_type] = node.send(status_type).to_sym
        statuses
      end
    end

    def update_sql(new_statuses)
      updates = new_statuses.map { |type, val| "#{type} = '#{val}'" }.join(',')
      where_statuses = current_statuses.map { |type, val| "#{type} = '#{val}'" }.join(' AND ')
      "UPDATE nodes SET #{updates} WHERE id = '#{node.id}' AND #{where_statuses}"
    end

    def update_statuses(statuses)
      result = Node.connection.execute(update_sql(statuses))
      rows_affected = result.respond_to?(:cmd_tuples) ? result.cmd_tuples : result # The jruby adapter does not return a PG::Result
      if rows_affected == 0
        raise StaleStatusChange, "Stale status change data for node #{node.id}"
      else
        create_status_changes(statuses)
        node.reload
      end
    end

    def create_status_changes(new_statuses)
      new_statuses.each do |(status_type, new_status)|
        node.status_changes.create!(
          from_status: current_statuses[status_type],
          to_status: new_status,
          status_type: status_type,
          response: response
        )
      end
    end

    def validate_status(new_status, status_type)
      unless valid_status_change?(new_status, status_type)
        current_status = current_statuses[status_type]
        message = "Cannot transition #{status_type} from #{current_status} to #{new_status}"
        if status_type == :current_client_status
          error_data = { current_status: current_status, attempted_status: new_status }
          raise InvalidClientStatusChange.new(message, error_data)
        else
          raise InvalidServerStatusChange.new(message)
        end
      end
    end

    def valid_status_change?(new_status, status_type)
      new_status && valid_state_changes(status_type).include?(new_status)
    end

    def valid_state_changes(status_type)
      current_status = current_statuses[status_type]
      VALID_STATE_CHANGES[status_type][current_status]
    end
  end
end

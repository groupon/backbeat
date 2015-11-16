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

require 'sidekiq'
require 'sidekiq/schedulable'

module Backbeat
  module Workers
    class HealNodes
      include Logging
      include Sidekiq::Worker
      include Sidekiq::Schedulable

      sidekiq_options retry: false, queue: Config.options[:async_queue]
      sidekiq_schedule Config.options[:schedules][:heal_nodes], last_run: true

      CLIENT_TIMEOUT_ERROR = "Client did not respond within the specified 'complete_by' time"
      UNEXPECTED_STATE_MESSAGE = "Node with expired 'complete_by' is not in expected state"

      def perform(last_run)
        last_run_time = Time.at(last_run)
        expired_node_details(last_run_time).each do |node_detail|
          node = node_detail.node

          if received_by_client?(node)
            info(message: CLIENT_TIMEOUT_ERROR, node: node.id, complete_by: node_detail.complete_by)
            Server.fire_event(Events::ClientError.new({ error: CLIENT_TIMEOUT_ERROR }), node)
          else
            info(message: UNEXPECTED_STATE_MESSAGE, node: node.id, complete_by: node_detail.complete_by)
          end
        end
      end

      private

      def expired_node_details(last_run_time)
        NodeDetail.where(complete_by: last_run_time..Time.now).select(:node_id, :complete_by)
      end

      def received_by_client?(node)
        node.current_server_status == "sent_to_client" && node.current_client_status == "received"
      end
    end
  end
end

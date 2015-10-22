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

require_relative 'base'

module ScheduledJobs
  class HealNodes < Base
    CLIENT_TIMEOUT_ERROR = "Client did not respond within the specified 'complete_by' time"
    UNEXPECTED_STATE_MESSAGE = "Node with expired 'complete_by' is not in expected state"
    SEARCH_PADDING = 1.hour # used in case the search does not run on time

    def perform
      resend_expired_nodes
    end

    private

    def resend_expired_nodes
      expired_node_details.each do |node_detail|
        node = node_detail.node

        if received_by_client?(node)
          info(source: self.class.to_s, message: CLIENT_TIMEOUT_ERROR, node: node.id, complete_by: node_detail.complete_by)
          Backbeat::Server.fire_event(Backbeat::Events::ClientError.new(CLIENT_TIMEOUT_ERROR), node)
        else
          info(source: self.class.to_s, message: UNEXPECTED_STATE_MESSAGE, node: node.id, complete_by: node_detail.complete_by)
        end
      end
    end

    def expired_node_details
      search_lower_bound = Time.now - Backbeat::Config.options[:job_frequency][:heal_nodes] - SEARCH_PADDING
      Backbeat::NodeDetail.where(complete_by: (search_lower_bound..Time.now)).select("node_id, complete_by")
    end

    def received_by_client?(node)
      node.current_server_status == "sent_to_client" && node.current_client_status == "received"
    end
  end
end

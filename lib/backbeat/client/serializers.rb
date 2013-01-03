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
  module Client
    class NodeSerializer
      def self.call(node)
        {
          id: node.id,
          mode: node.mode,
          name: node.name,
          workflow_id: node.workflow_id,
          parent_id: node.parent_id,
          user_id: node.user_id,
          client_data: node.client_data,
          metadata: node.client_metadata,
          subject: node.subject,
          decider: node.decider,
          workflow_name: node.workflow_name,
          current_server_status: node.current_server_status,
          current_client_status: node.current_client_status
        }
      end
    end

    class NotificationSerializer
      def self.call(node, message, error = nil)
        {
          notification: {
            type: node.class.to_s,
            id: node.id,
            name: node.name,
            subject: node.subject,
            message: message
          },
          error: ErrorSerializer.call(error)
        }
      end
    end

    class ErrorSerializer
      def self.call(error)
        case error
        when StandardError
          {
            error_klass: error.class.to_s,
            message: error.message
          }.tap { |data| data[:backtrace] = error.backtrace if error.backtrace }
        when String
          { error_klass: error.class.to_s, message: error }
        else
          error
        end
      end
    end
  end
end

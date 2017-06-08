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

require 'httparty'

module Backbeat
  module Client
    class << self
      def notify_of(node, message, error = nil)
        Instrument.instrument("client_notify", { node: node.id }) do
          user = node.user
          if url = user.notification_endpoint
            notification = NotificationPresenter.new(message, error).present(node)
            response = post(url, notification)
            raise HttpError.new("HTTP request for notification failed", response) unless response.success?
          end
        end
      end

      def perform(node)
        Instrument.instrument("client_perform_activity", { node: node.id }) do
          if node.decision? && node.user.decision_endpoint
            make_decision(NodePresenter.present(node), node.user)
          else
            perform_activity(NodePresenter.present(node), node.user)
          end
        end
      end

      private

      def perform_activity(activity, user)
        if url = user.activity_endpoint
          response = post(url, { activity: activity })
          raise HttpError.new("HTTP request for activity failed", response) unless response.success?
        end
      end

      def make_decision(decision, user)
        if url = user.decision_endpoint
          response = post(url, { decision: decision })
          raise HttpError.new("HTTP request for decision failed", response) unless response.success?
        end
      end

      def post(url, params = {})
        HTTParty.post(url, {
          body: params.to_json,
          headers: { "Content-Type" => "application/json" }
        })
      rescue => e
        raise HttpError.new("Could not POST #{url}, error: #{e.class}, #{e.message}")
      end
    end
  end
end

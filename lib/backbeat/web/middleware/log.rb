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
  module Web
    module Middleware
      class Log
        TRANSACTION_ID_HEADER = 'X-backbeat-tid'.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          t0 = Time.now
          tid = Logger.tid(:set)

          Logger.info({
            message: "Request Start",
            path: env['PATH_INFO']
          })

          status, headers, body = response = @app.call(env)

          Logger.info({
            message: "Request Complete",
            request: request_info(env),
            response: {
              status: status,
              duration: Time.now - t0,
            }
          })

          headers[TRANSACTION_ID_HEADER] = tid
          Logger.tid(:clear)

          response
        end

        def request_info(env)
          request = Rack::Request.new(env)
          route_info = env["rack.routing_args"].try(:[], :route_info)
          if route_info
            options = route_info.instance_variable_get("@options")
            {
              version: options[:version],
              namespace: options[:namespace],
              method: options[:method],
              path: request.path_info,
              params: request.params
            }
          end
        end
      end
    end
  end
end

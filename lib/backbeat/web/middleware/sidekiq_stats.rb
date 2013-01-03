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
      class SidekiqStats
        def initialize(app)
          @app = app
        end

        ENDPOINT = '/sidekiq_stats'

        def call(env)
          if env['PATH_INFO'] == ENDPOINT
            stats = Sidekiq::Stats.new
            history = Sidekiq::Stats::History.new(1)
            data = {
              latency: latency(stats),
              today: {
                processed: history.processed.values[0],
                failed: history.failed.values[0]
              },
              processed: stats.processed,
              failed: stats.failed,
              enqueued: stats.enqueued,
              scheduled: stats.scheduled_size,
              retry_size: stats.retry_size
            }
            [200, { "Content-Type" => "application/json" }, [data.to_json]]
          else
            @app.call(env)
          end
        end

        def latency(stats)
          stats.queues.keys.inject({}) do |h, q|
            h[q] = Sidekiq::Queue.new(q).latency
            h
          end
        end
      end
    end
  end
end

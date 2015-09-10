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

require 'backbeat/instrument'

module Backbeat
  module Schedulers
    class AsyncEvent
      def initialize(&timer)
        @timer = timer
      end

      def call(event, node)
        time = @timer.call(node)
        Workers::AsyncWorker.schedule_async_event(event, node, { time: time })
      end
    end

    ScheduleNow = AsyncEvent.new { Time.now }
    ScheduleAt  = AsyncEvent.new { |node| node.fires_at }

    DEFAULT_RETRIES = 4

    ScheduleRetry = AsyncEvent.new do |node|
      tries = DEFAULT_RETRIES - node.retries_remaining
      tries = 0 if tries < 0
      backoff = node.retry_interval + (tries ** 4) + (rand(0..30) * (tries + 1))
      Time.now + backoff.minutes
    end

    class PerformEvent
      def self.call(event, node)
        Instrument.instrument(event.name, { node: node }) do
          event.call(node)
        end
      end
    end
  end
end

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

require 'spec_helper'

describe Backbeat::Web::Middleware::SidekiqStats, :api_test do

  context '/sidekiq_stats' do
    it 'catches the request, returns 200 and queue stats' do
      stats = double(Sidekiq::Stats, processed: 23, failed: 42, enqueued: 666, scheduled_size: 0, retry_size: 123, queues: {"queue1" => 0, "queue2" => 0} )
      history = double(Sidekiq::Stats::History, processed: {"2013-11-08" => 15}, failed: {"2013-11-08" => 19})

      q1 = double(Sidekiq::Queue, latency: 10)
      q2 = double(Sidekiq::Queue, latency: 20)
      expect(Sidekiq::Queue).to receive(:new).with("queue1").and_return(q1)
      expect(Sidekiq::Queue).to receive(:new).with("queue2").and_return(q2)
      allow(Sidekiq::Stats).to receive_messages(new: stats)

      expect(Sidekiq::Stats::History).to receive(:new).with(1).and_return(history)

      response = get '/sidekiq_stats'
      expect(response.status).to eq(200)

      JSON.parse(response.body) == {
        "latency" => { "queue1" => 10, "queue2" => 20 },
        "today"   => { "processed" => 15, "failed" => 19 },
        "processed" => 23,
        "failed"    => 42,
        "enqueued"  => 666,
        "scheduled_size" => 0,
        "retry_size" => 123
      }
    end
  end
end

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

describe Backbeat::Workers::LogQueues do
  context "log_count" do
    def expect_info(type, count_subject, count)
      expect(Backbeat::Logger).to receive(:add) do |_, log|
        expect(log[:source]).to eq("Backbeat::Workers::LogQueues")
        expect(log[:data][:type]).to eq(type)
        expect(log[:data][:subject]).to eq(count_subject)
        expect(log[:data][:count]).to eq(count)
      end
    end

    it "logs info with the correct info" do
      allow_any_instance_of(Sidekiq::RetrySet).to receive(:size).and_return(1)
      allow_any_instance_of(Sidekiq::ScheduledSet).to receive(:size).and_return(3)

      sidekiq_queues = {"queue_1"=>10, "queue_2"=>0}
      allow_any_instance_of(Sidekiq::Stats).to receive(:queues).and_return(sidekiq_queues)

      expect_info(:queue, "retry", 1)
      expect_info(:queue, "schedule" ,3)
      expect_info(:queue, "queue_1", 10)
      expect_info(:queue, "queue_2", 0)

      subject.perform
    end
  end
end

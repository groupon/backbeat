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

require "spec_helper"

describe Backbeat::Schedulers do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  class MockEvent
    def self.call(node)
      true
    end
  end

  before do
    node.node_detail.retry_interval = 60
    node.fires_at = Time.now + 20.days
  end

  context "PerformEvent" do
    it "logs the node, event name, and args" do
      expect(Backbeat::Instrument).to receive(:instrument).with(
        "MockEvent",
        { node: node }
      )

      Backbeat::Schedulers::PerformEvent.call(MockEvent, node)
    end

    it "calls the event with the node" do
      expect(MockEvent).to receive(:call).with(node)

      Backbeat::Schedulers::PerformEvent.call(MockEvent, node)
    end
  end

  context "ScheduleAt" do
    it "schedules an async event with node fires_at as the time" do
      expect(Backbeat::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now + 20.days }
      )
      Backbeat::Schedulers::ScheduleAt.call(MockEvent, node)
    end
  end

  context "ScheduleRetry" do
    let(:now) { Time.now }

    retries = [
      { retries_remaining: 51, lower_bound: 0.minutes, upper_bound: 30.minutes },
      { retries_remaining: 4, lower_bound: 0.minutes, upper_bound: 30.minutes },
      { retries_remaining: 1, lower_bound: 81.minutes, upper_bound: 201.minutes }
    ]

    retries.each do |params|
      it "calculates retry interval by progressively backing off as remaining retries decrease from 4" do
        node.node_detail.update_attributes({
          retries_remaining: params[:retries_remaining],
          retry_interval: 20.minutes
        })

        expect(Backbeat::Workers::AsyncWorker).to receive(:schedule_async_event) do |event, evented_node, args|
          expect(event).to eq(MockEvent)
          expect(evented_node).to eq(node)

          time = args[:time]

          expect(time).to be >= now + node.retry_interval + params[:lower_bound]
          expect(time).to be <= now + node.retry_interval + params[:upper_bound]
        end

        Backbeat::Schedulers::ScheduleRetry.call(MockEvent, node)
      end

      it "updates the node's fires_at time" do
        node.node_detail.update_attributes({
          retries_remaining: params[:retries_remaining],
          retry_interval: 20.minutes
        })

        Backbeat::Schedulers::ScheduleRetry.call(MockEvent, node)
        time = node.fires_at

        expect(time).to be >= now + node.retry_interval + params[:lower_bound]
        expect(time).to be <= now + node.retry_interval + params[:upper_bound]
      end
    end
  end

  context "ScheduleNow" do
    it "schedules an async event with now as the scheduled time" do
      expect(Backbeat::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now }
      )
      Backbeat::Schedulers::ScheduleNow.call(MockEvent, node)
    end
  end
end

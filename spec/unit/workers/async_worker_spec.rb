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

describe Backbeat::Workers::AsyncWorker do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  after do
    Sidekiq::ScheduledSet.new.clear
  end

  context ".schedule_async_event" do
    it "calls an event with the node" do
      expect(Backbeat::Events::MarkChildrenReady).to receive(:call).with(node)
      Backbeat::Workers::AsyncWorker.schedule_async_event(Backbeat::Events::MarkChildrenReady, node, { time: Time.now, retries: 0 })
      Backbeat::Workers::AsyncWorker.drain
    end
  end

  context "#perform" do
    it "fires the event with the node" do
      expect(Backbeat::Server).to receive(:fire_event) do |event, event_node, scheduler|
        expect(event).to eq(Backbeat::Events::MarkChildrenReady)
        expect(event_node).to eq(node)
        expect(scheduler).to eq(Backbeat::Schedulers::PerformEvent)
      end

      Backbeat::Workers::AsyncWorker.new.perform(
        Backbeat::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 0 }
      )
    end

    it "retries the job if there is an error in running the event" do
      expect(Backbeat::Events::MarkChildrenReady).to receive(:call) { raise "Event Failed" }

      Backbeat::Workers::AsyncWorker.new.perform(
        Backbeat::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 1 }
      )

      expect(Backbeat::Workers::AsyncWorker.jobs.count).to eq(1)
    end

    it "retries the job if there is an error deserializing the node" do
      expect(Backbeat::Node).to receive(:find) { raise "Could not connect to the database" }

      expect {
        Backbeat::Workers::AsyncWorker.new.perform(
          Backbeat::Events::MarkChildrenReady.name,
          { "node_class" => node.class.name, "node_id" => node.id },
          { "retries" => 1 }
        )
      }.to raise_error(Backbeat::DeserializeError)

      expect(Backbeat::Workers::AsyncWorker.jobs.count).to eq(0)
    end

    it "puts the node in an errored state when out of retries" do
      expect(Backbeat::Events::MarkChildrenReady).to receive(:call) { raise "Event Failed" }

      Backbeat::Workers::AsyncWorker.new.perform(
        Backbeat::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 0 }
      )

      expect(Backbeat::Workers::AsyncWorker.jobs.count).to eq(0)
      expect(node.reload.current_server_status).to eq("errored")
    end

    it "logs if we blow up when trying to retry" do
      allow(Backbeat::Workers::AsyncWorker).to receive(:perform_at) { raise "Error Connecting to Redis" }

      allow(subject).to receive(:error) do |message|
        expect(message[:status]).to eq(:uncaught_exception)
        expect(message[:error].message).to eq("Error Connecting to Redis")
      end

      expect {
        subject.perform(
          Backbeat::Events::MarkChildrenReady.name,
          { "node_class" => node.class.name, "node_id" => node.id },
          { "retries" => 1 }
        )
      }.to raise_error("Error Connecting to Redis")
    end
  end

  context ".find_job" do
    it "finds the job for the event and node" do
      Sidekiq::Testing.disable! do
        Backbeat::Workers::AsyncWorker.schedule_async_event(
          Backbeat::Events::RetryNode,
          node,
          { time: Time.now + 1.hour }
        )

        job = Backbeat::Workers::AsyncWorker.find_job(Backbeat::Events::RetryNode, node)

        expect(job.item['args'][1]['node_id']).to eq(node.id)
      end
    end
  end

  context ".remove_job" do
    it "deletes the job for the event and node" do
      Sidekiq::Testing.disable! do
        Backbeat::Workers::AsyncWorker.schedule_async_event(
          Backbeat::Events::RetryNode,
          node,
          { time: Time.now + 1.hour }
        )

        job = Backbeat::Workers::AsyncWorker.find_job(Backbeat::Events::RetryNode, node)

        expect(job.item['args'][1]['node_id']).to eq(node.id)

        Backbeat::Workers::AsyncWorker.remove_job(Backbeat::Events::RetryNode, node)

        job = Backbeat::Workers::AsyncWorker.find_job(Backbeat::Events::RetryNode, node)

        expect(job).to be_nil
      end
    end
  end
end

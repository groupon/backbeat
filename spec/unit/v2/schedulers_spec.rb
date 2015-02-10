require "spec_helper"

describe V2::Schedulers, v2: true do

  class MockNode
    def id
      1
    end

    def retry_interval
      60
    end

    def fires_at
      Time.now + 20.days
    end
  end

  class MockEvent
    def self.call(node)
      true
    end
  end

  let(:node) { MockNode.new }

  context "NowScheduler" do
    it "logs the node, event name, and args" do
      expect(Instrument).to receive(:instrument).with(
        node,
        "MockEvent",
        { server_retries_remaining: 1 }
      )

      V2::Schedulers::NowScheduler.new(1).schedule(MockEvent, node)
    end

    it "calls the event with the node" do
      expect(MockEvent).to receive(:call).with(node)

      V2::Schedulers::NowScheduler.schedule(MockEvent, node)
    end

    it "fires server error event when an error is raised" do
      error = StandardError.new

      expect(MockEvent).to receive(:call).with(node) do
        raise error
      end

      expect(V2::Server).to receive(:server_error).with(
        MockEvent,
        node,
        { error: error, server_retries_remaining: 0 }
      )

      expect { V2::Schedulers::NowScheduler.schedule(MockEvent, node) }.to raise_error(error)
    end
  end

  context "RetryScheduler" do
    it "schedules an async event with a 30 second back off" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 30.seconds,
        0
      )
      V2::Schedulers::RetryScheduler.schedule(MockEvent, node)
    end

    it "schedules an async event with the set number of retries" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 30.seconds,
        5
      )
      V2::Schedulers::RetryScheduler.new(5).schedule(MockEvent, node)
    end
  end

  context "AtScheduler" do
    it "schedules an async event with node fires_at as the time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 20.days,
        4
      )
      V2::Schedulers::AtScheduler.schedule(MockEvent, node)
    end
  end

  context "IntervalScheduler" do
    it "schedules an async event with node retry_interval from now as the time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 60.minutes,
        4
      )
      V2::Schedulers::IntervalScheduler.schedule(MockEvent, node)
    end
  end

  context "AsyncScheduler" do
    it "schedules an async event with now as the scheduled time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now,
        4
      )
      V2::Schedulers::AsyncScheduler.schedule(MockEvent, node)
    end
  end
end

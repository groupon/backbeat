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

  context "ScheduleIn" do
    it "schedules an async event with node retry_interval from now as the time" do
      expect(Backbeat::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now + 60.minutes }
      )
      Backbeat::Schedulers::ScheduleIn.call(MockEvent, node)
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

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
        node.node_detail.update_attributes(retries_remaining: params[:retries_remaining])

        expect(Backbeat::Workers::AsyncWorker).to receive(:schedule_async_event) do |event, evented_node, args|
          expect(event).to eq(MockEvent)
          expect(evented_node).to eq(node)

          time = args[:time]

          expect(time).to be >= now + node.retry_interval.minutes + params[:lower_bound]
          expect(time).to be <= now + node.retry_interval.minutes + params[:upper_bound]
        end

        Backbeat::Schedulers::ScheduleRetry.call(MockEvent, node)
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

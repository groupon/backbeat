require "spec_helper"

describe V2::Async, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
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
      expect(Instrument).to receive(:instrument).with(
        "MockEvent",
        { node: node, server_retries_remaining: 1 }
      )

      V2::Async::PerformEvent.new({ retries: 1 }).call(MockEvent, node)
    end

    it "calls the event with the node" do
      expect(MockEvent).to receive(:call).with(node)

      V2::Async::PerformEvent.call(MockEvent, node)
    end

    context "rescuing an error" do
      let(:error) { StandardError.new }

      before do
        allow(MockEvent).to receive(:call) { raise error }
      end

      it "schedules the task with a delay with one less retry" do
        expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(MockEvent, node, { time: Time.now + 30.seconds, retries: 1 })

        expect { V2::Async::PerformEvent.new({ retries: 2 }).call(MockEvent, node) }.to raise_error
      end

      it "notifies the client if there are no remaining retries" do
        expect(V2::Client).to receive(:notify_of).with(node, "error", error)

        expect { V2::Async::PerformEvent.call(MockEvent, node) }.to raise_error
      end

      it "updates the node status to errored if there are no remaining retries" do
        expect { V2::Async::PerformEvent.call(MockEvent, node) }.to raise_error

        expect(node.current_server_status).to eq("errored")
      end
    end
  end

  context "Backoff" do
    it "schedules an async event with a 30 second back off" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now + 30.seconds }
      )
      V2::Async::Backoff.call(MockEvent, node)
    end
  end

  context "ScheduleAt" do
    it "schedules an async event with node fires_at as the time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now + 20.days }
      )
      V2::Async::ScheduleAt.call(MockEvent, node)
    end
  end

  context "ScheduleIn" do
    it "schedules an async event with node retry_interval from now as the time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now + 60.minutes }
      )
      V2::Async::ScheduleIn.call(MockEvent, node)
    end
  end

  context "ScheduleNow" do
    it "schedules an async event with now as the scheduled time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        { time: Time.now }
      )
      V2::Async::ScheduleNow.call(MockEvent, node)
    end
  end
end

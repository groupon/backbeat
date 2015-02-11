require "spec_helper"

describe V2::Schedulers, v2: true do

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
        node,
        "MockEvent",
        { server_retries_remaining: 1 }
      )

      V2::Schedulers::PerformEvent.new(1).call(MockEvent, node)
    end

    it "calls the event with the node" do
      expect(MockEvent).to receive(:call).with(node)

      V2::Schedulers::PerformEvent.call(MockEvent, node)
    end

    context "rescuing an error" do
      let(:error) { StandardError.new }

      before do
        allow(MockEvent).to receive(:call) { raise error }
      end

      it "schedules the task with a delay with one less retry" do
        expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(MockEvent, node, Time.now + 30.seconds, 1)

        expect { V2::Schedulers::PerformEvent.new(2).call(MockEvent, node) }.to raise_error
      end

      it "notifies the client if there are no remaining retries" do
        expect(V2::Client).to receive(:notify_of).with(node, "error", error)

        expect { V2::Schedulers::PerformEvent.call(MockEvent, node) }.to raise_error
      end

      it "updates the node status to errored if there are no remaining retries" do
        expect { V2::Schedulers::PerformEvent.call(MockEvent, node) }.to raise_error

        expect(node.current_server_status).to eq("errored")
      end
    end
  end

  context "AsyncEventBackoff" do
    it "schedules an async event with a 30 second back off" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 30.seconds,
        4
      )
      V2::Schedulers::AsyncEventBackoff.call(MockEvent, node)
    end
  end

  context "AsyncEventAt" do
    it "schedules an async event with node fires_at as the time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 20.days,
        4
      )
      V2::Schedulers::AsyncEventAt.call(MockEvent, node)
    end
  end

  context "AsyncEventInterval" do
    it "schedules an async event with node retry_interval from now as the time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now + 60.minutes,
        4
      )
      V2::Schedulers::AsyncEventInterval.call(MockEvent, node)
    end
  end

  context "AsyncEvent" do
    it "schedules an async event with now as the scheduled time" do
      expect(V2::Workers::AsyncWorker).to receive(:schedule_async_event).with(
        MockEvent,
        node,
        Time.now,
        4
      )
      V2::Schedulers::AsyncEvent.call(MockEvent, node)
    end
  end
end

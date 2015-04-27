require "spec_helper"

describe V2::Workers::AsyncWorker, v2: true do

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "schedule_async_event" do
    it "calls an event with the node" do
      expect(V2::Events::ChildrenReady).to receive(:call).with(node)
      V2::Workers::AsyncWorker.schedule_async_event(V2::Events::ChildrenReady, node, Time.now, 0)
      V2::Workers::AsyncWorker.drain
    end
  end

  context "perform" do
    it "fires the event with the node" do
      expect(V2::Server).to receive(:fire_event) do |event, event_node, scheduler|
        expect(event).to eq(V2::Events::MarkChildrenReady)
        expect(event_node).to eq(node)
        expect(scheduler).to be_a(V2::Schedulers::PerformEvent)
      end

      V2::Workers::AsyncWorker.new.perform(
        V2::Events::MarkChildrenReady.name,
        node.class.name,
        node.id,
        0
      )
    end

    it "retries the job if the node cannot be found" do
      V2::Workers::AsyncWorker.new.perform(
        V2::Events::MarkChildrenReady.name,
        node.class.name,
        5,
        0
      )

      expect(V2::Workers::AsyncWorker.jobs.count).to eq(1)
    end
  end
end

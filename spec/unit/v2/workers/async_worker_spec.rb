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
      expect(V2::Events::MarkChildrenReady).to receive(:call).with(node)
      V2::Workers::AsyncWorker.schedule_async_event(V2::Events::MarkChildrenReady, node, { time: Time.now, retries: 0 })
      V2::Workers::AsyncWorker.drain
    end
  end

  context "perform" do
    it "fires the event with the node" do
      expect(V2::Server).to receive(:fire_event) do |event, event_node, scheduler|
        expect(event).to eq(V2::Events::MarkChildrenReady)
        expect(event_node).to eq(node)
        expect(scheduler).to eq(V2::Schedulers::PerformEvent)
      end

      V2::Workers::AsyncWorker.new.perform(
        V2::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 0 }
      )
    end

    it "retries the job if there is an error in running the event" do
      expect(V2::Events::MarkChildrenReady).to receive(:call) { raise "Event Failed" }

      V2::Workers::AsyncWorker.new.perform(
        V2::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 1 }
      )

      expect(V2::Workers::AsyncWorker.jobs.count).to eq(1)
    end

    it "retries the job if there is an error deserializing the node" do
      expect(V2::Node).to receive(:find) { raise "Could not connect to the database" }

      V2::Workers::AsyncWorker.new.perform(
        V2::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 1 }
      )

      expect(V2::Workers::AsyncWorker.jobs.count).to eq(1)
    end

    it "puts the node in an errored state when out of retries" do
      expect(V2::Events::MarkChildrenReady).to receive(:call) { raise "Event Failed" }

      V2::Workers::AsyncWorker.new.perform(
        V2::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 0 }
      )

      expect(V2::Workers::AsyncWorker.jobs.count).to eq(0)
      expect(node.reload.current_server_status).to eq("errored")
    end

    it "logs if we blow up when trying to retry" do
      allow(V2::Workers::AsyncWorker).to receive(:perform_at) { raise "Error Connecting to Redis" }

      allow(subject).to receive(:error) do |message|
        expect(message[:status]).to eq(:uncaught_exception)
        expect(message[:error].message).to eq("Error Connecting to Redis")
      end

      subject.perform(
        V2::Events::MarkChildrenReady.name,
        { "node_class" => node.class.name, "node_id" => node.id },
        { "retries" => 1 }
      )
    end
  end
end

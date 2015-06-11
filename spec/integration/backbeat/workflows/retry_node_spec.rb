require 'spec_helper'
require "spec/helper/request_helper"
require "spec/helper/sidekiq_helper"

describe Backbeat do
  include Rack::Test::Methods
  include RequestHelper
  include SidekiqHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node_running, user: user) }
  let(:activity_node) { workflow.children.first.children.first }

  before do
    header 'CLIENT_ID', user.id
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "client error" do
    it "retries with backoff and then succeeds" do
      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node))
        .to_return(:status => 200, :body => "", :headers => {})

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_node.node_detail.retries_remaining).to eq(4)

      response = put "v2/events/#{activity_node.id}/status/errored"

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_node.node_detail.retries_remaining).to eq(3)

      response = put "v2/events/#{activity_node.id}/status/completed"
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      Backbeat::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_node.parent.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end

    it "retries full number of retries available and fails" do
      activity_node.reload.attributes.should include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      activity_node.node_detail.update_attributes(retries_remaining: 2)
      expect(activity_node.node_detail.retries_remaining).to eq(2)

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node))
        .to_return(:status => 200, :body => "", :headers => {})

      2.times do |i|
        response = put "v2/events/#{activity_node.id}/status/errored"

        Backbeat::Workers::AsyncWorker.drain

        expect(activity_node.reload.attributes).to include(
          "current_client_status" => "received",
          "current_server_status" => "sent_to_client"
        )
        expect(activity_node.node_detail.retries_remaining).to eq(1-i)
      end

      response = put "v2/events/#{activity_node.id}/status/errored"
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "errored",
        "current_server_status" => "sent_to_client"
      )
    end

    it "resets the node to handle errors in weird states" do
      node = workflow.children.first

      2.times do
        FactoryGirl.create(
          :node,
          parent: node,
          user: user,
          workflow: workflow,
          current_server_status: :ready,
          current_client_status: :ready,
        )
      end

      allow(Backbeat::Client).to receive(:perform_action) do |node|
        Backbeat::Server.fire_event(Backbeat::Events::ClientComplete, node)
      end

      put "v2/events/#{node.id}/status/errored"

      Backbeat::Workers::AsyncWorker.drain
      node.reload

      expect(node.current_server_status).to eq("complete")
      expect(node.current_client_status).to eq("complete")
    end
  end

  context "server error" do
    it "sends a message to the client after a set number of retries fails" do
      Timecop.freeze
      expect(Backbeat::Events::StartNode).to receive(:call).exactly(5).times do
        raise StandardError.new("start node failed")
      end

      Backbeat::Server.fire_event(Backbeat::Events::StartNode, activity_node)

      4.times do
        Timecop.travel(Time.now + 31.seconds)
        expect { soft_drain }.to raise_error
        expect(activity_node.current_server_status).to eq("sent_to_client")
      end

      Timecop.travel(Time.now + 31.seconds)
      expect { soft_drain }.to raise_error
      expect(activity_node.reload.current_server_status).to eq("errored")
    end
  end
end


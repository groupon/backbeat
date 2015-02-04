require 'spec_helper'
require "spec/helper/request_helper"
require 'sidekiq/testing'
require "spec/helper/sidekiq_helper"

describe V2::Api, v2: true do
  include Rack::Test::Methods
  include RequestHelper
  include SidekiqHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow, user: user) }

  before do
    header 'CLIENT_ID', user.uuid
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
    Sidekiq::Testing.fake!
  end

  context "nodes with fires_at" do
    it "does not run a node with fires_at until time has expired" do
      Timecop.freeze

      signal_node = FactoryGirl.create(
        :v2_node,
        name: "signal with timed node",
        user: user,
        workflow: workflow,
        current_server_status: :processing_children,
        current_client_status: :complete,
      )

      timed_activity_node = FactoryGirl.create(
        :v2_node,
        name: "timed node",
        parent: signal_node,
        fires_at: Time.now + 10.minutes,
        mode: :non_blocking,
        user: user,
        current_server_status: :ready,
        current_client_status: :ready,
        workflow: workflow
      )

      activity_node = FactoryGirl.create(
        :v2_node,
        name: "following timed node",
        parent: signal_node,
        user: user,
        workflow: workflow,
        current_server_status: :ready,
        current_client_status: :ready,
        mode: :blocking
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node).to_json)
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Server::fire_event(V2::Server::ScheduleNextNode, signal_node)

      soft_drain
      expect(timed_activity_node.reload.current_server_status).to eq("started")

      soft_drain
      expect(activity_node.reload.current_server_status).to eq("sent_to_client")

      put "/events/#{activity_node.id}/status/completed"
      soft_drain
      expect(activity_node.reload.current_server_status).to eq("complete")

      soft_drain
      expect(signal_node.reload.current_server_status).to eq("processing_children")
      expect(timed_activity_node.reload.current_server_status).to eq("started")

      # drains schedule next node on workflow
      soft_drain

      Timecop.travel(Time.now + 11.minutes)

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(timed_activity_node).to_json)
        .to_return(:status => 200, :body => "", :headers => {})

      soft_drain

      expect(timed_activity_node.reload.current_server_status).to eq("sent_to_client")
      put "/events/#{timed_activity_node.id}/status/completed"

      soft_drain
      expect(timed_activity_node.reload.current_server_status).to eq("complete")

      soft_drain
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

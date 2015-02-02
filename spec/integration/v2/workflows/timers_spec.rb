require 'spec_helper'
require "spec/helper/request_helper"
require 'sidekiq/testing'

describe V2::Api, v2: true do
  include Rack::Test::Methods
  include RequestHelper

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

  # Acknowledges perform_in time and does not drain jobs that a drained job enqueues
  def soft_drain
    jobs = V2::Workers::AsyncWorker.jobs
    0.upto(jobs.count - 1) do |i|
      job = jobs[i]
      if !job["at"] || Time.now.to_f > job["at"]
        worker = V2::Workers::AsyncWorker.new
        worker.jid = job['jid']
        args = job['args']
        worker.perform(*args)
        jobs[i] = nil
      end
    end
    jobs.compact!
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

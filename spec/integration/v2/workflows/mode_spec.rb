require 'spec_helper'
require "spec/helper/request_helper"

describe V2::Api, v2: true do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:v2_user) { FactoryGirl.create(:v2_user) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow, user: v2_user) }

  before do
    header 'CLIENT_ID', v2_user.uuid
  end

  context "modes" do
    it "completes a workflow with blocking, non_blocking and fire_and_forget nodes" do
      response = post "v2/workflows/#{v2_workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      signal_node = v2_workflow.children.where(id: signal['id']).first
      expect(signal_node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      decision_to_make = FactoryGirl.build(
        :client_decision,
        id: signal_node.id,
        name: 'test',
        parentId: signal_node.parent_id,
        userId: signal_node.user_id,
        decider: signal_node.decider,
        clientData: signal_node.client_node_detail.data,
        metadata: signal_node.client_node_detail.metadata,
        subject: signal_node.subject
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => {decision: decision_to_make})
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::AsyncWorker.drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "v2/events/#{signal_node.id}/status/deciding"

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity_1 = FactoryGirl.build(:client_activity_post_to_decision).merge(mode: :non_blocking)
      activity_2 = FactoryGirl.build(:client_activity_post_to_decision)
      activity_3 = FactoryGirl.build(:client_activity_post_to_decision).merge(mode: :non_blocking)
      activity_4 = FactoryGirl.build(:client_activity_post_to_decision).merge(mode: :fire_and_forget)

      activities_to_post = { "args" => { "decisions" => [activity_1, activity_2, activity_3, activity_4] }}

      response = post "v2/events/#{signal_node.id}/decisions", activities_to_post

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.children.count).to eq(4)

      response = put "v2/events/#{signal_node.id}/status/deciding_complete"

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_nodes = signal_node.children
      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      activity_nodes[0..1].each do |activity_node|
        WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
          .with(:body => activity_hash(activity_node))
          .to_return(:status => 200, :body => "", :headers => {})
      end

      V2::Workers::AsyncWorker.drain

      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      put "v2/events/#{activity_nodes[0].id}/status/completed"
      put "v2/events/#{activity_nodes[1].id}/status/completed"

      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_nodes[2..3].each do |activity_node|
        WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
          .with(:body => activity_hash(activity_node).to_json)
          .to_return(:status => 200, :body => "", :headers => {})
      end

      V2::Workers::AsyncWorker.drain

      expect(activity_nodes[0].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_nodes[1].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      put "v2/events/#{activity_nodes[2].id}/status/completed"

      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      V2::Workers::AsyncWorker.drain

      expect(activity_nodes[2].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      put "v2/events/#{activity_nodes[3].id}/status/completed"

      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      V2::Workers::AsyncWorker.drain

      expect(activity_nodes[3].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end

    it "completes a workflow with two signals" do
      response = post "v2/workflows/#{v2_workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        client_metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      signal_node = v2_workflow.children.where(id: signal['id']).first
      expect(signal_node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      response_2 = post "v2/workflows/#{v2_workflow.id}/signal/test_2", options: {
        client_data: { data: '124' },
        client_metadata: { metadata: '457'}
      }

      expect(response_2.status).to eq(201)

      signal_2 = JSON.parse(response_2.body)
      signal_node_2 = v2_workflow.children.where(id: signal_2['id']).first

      expect(signal_node_2.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      decision_to_make = FactoryGirl.build(
        :client_decision,
        id: signal_node.id,
        name: 'test',
        parentId: signal_node.parent_id,
        userId: signal_node.user_id,
        decider: signal_node.decider,
        clientData: signal_node.client_node_detail.data,
        metadata: signal_node.client_node_detail.metadata,
        subject: signal_node.subject
      )
      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => {decision: decision_to_make})
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::AsyncWorker.drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "v2/events/#{signal_node.id}/status/deciding"
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity = FactoryGirl.build(:client_activity_post_to_decision)
      activities_to_post = { "args" => { "decisions" => [activity] }}
      response = post "v2/events/#{signal_node.id}/decisions", activities_to_post

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.children.count).to eq(1)

      response = put "v2/events/#{signal_node.id}/status/deciding_complete"
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_node = signal_node.children.first
      expect(signal_node.children[0].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node))
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "v2/events/#{activity_node.id}/status/completed"
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      decision_to_make_2 = FactoryGirl.build(
        :client_decision,
        id: signal_node_2.id,
        name: 'test_2',
        parentId: signal_node_2.parent_id,
        userId: signal_node_2.user_id,
        decider: signal_node_2.decider,
        clientData: signal_node_2.client_node_detail.data,
        metadata: signal_node_2.client_node_detail.metadata,
        subject: signal_node_2.subject
      )
      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => {decision: decision_to_make_2})
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "v2/events/#{signal_node_2.id}/status/deciding"
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity = FactoryGirl.build(:client_activity_post_to_decision)
      activity_to_post_signal_2 = { "args" => { "decisions" => [activity] }}
      response = post "v2/events/#{signal_node_2.id}/decisions", activity_to_post_signal_2

      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node_2.reload.children.count).to eq(1)

      response = put "v2/events/#{signal_node_2.id}/status/deciding_complete"
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_node_signal_2 = signal_node_2.children.first
      expect(activity_node_signal_2.reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node_signal_2))
        .to_return(:status => 200, :body => "", :headers => {})
      V2::Workers::AsyncWorker.drain

      expect(activity_node_signal_2.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "v2/events/#{activity_node_signal_2.id}/status/completed"

      V2::Workers::AsyncWorker.drain

      expect(activity_node_signal_2.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_node_2.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

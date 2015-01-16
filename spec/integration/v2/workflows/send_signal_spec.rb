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
    header 'CLIENT_ID', v2_user.id
  end

  context "POST /workflows/:id/signal" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post "/workflows/#{v2_workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        client_metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      node = v2_workflow.nodes.where(id: signal['id']).first
      expect(node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      decision_to_make = FactoryGirl.build(
        :client_decision,
        id: node.id,
        name: :test,
        parentId: node.parent_id,
        userId: node.user_id,
        decider: v2_workflow.decider,
        subject: v2_workflow.subject
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => {decision: decision_to_make}.to_json)
        .to_return(:status => 200, :body => "", :headers => {})
      V2::Workers::AsyncWorker.drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "/events/#{node.id}/status/deciding"
      expect(node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity= FactoryGirl.build(:client_activity_post_to_decision)
      activity_to_post = { "args" => { "decisions" => [activity] }}
      response = post "events/#{node.id}/decisions", activity_to_post

      expect(node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(node.reload.children.count).to eq(1)

      response = put "/events/#{node.id}/status/deciding_complete"
      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      activity_node = node.children.first
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(activity_node).to_json)
        .to_return(:status => 200, :body => "", :headers => {})
      V2::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )

      response = put "/events/#{activity_node.id}/status/completed"
      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      V2::Workers::AsyncWorker.drain

      expect(activity_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

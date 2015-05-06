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

  context "flags" do
    it "completes a workflow with a flag" do
      response = post "v2/workflows/#{v2_workflow.id}/signal/test", options: {
        client_data: { data: '123' },
          client_metadata: { metadata: '456'}
      }
      expect(response.status).to eq(201)
      signal = JSON.parse(response.body)

      signal_node = v2_workflow.children.where(id: signal['id']).first
      expect(signal_node.attributes).to include(
        "current_server_status"=>"ready",
        "current_client_status"=>"ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(signal_node, {current_server_status: :sent_to_client, current_client_status: :received}))
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

      flag = {name: "my_flag", type: "flag"}
      activity = FactoryGirl.build(:client_activity_post_to_decision).merge(mode: :non_blocking)

      children_to_post = { "args" => { "decisions" => [flag, activity] }}

      response = post "v2/events/#{signal_node.id}/decisions", children_to_post

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )
      expect(signal_node.reload.children.count).to eq(2)


      response = put "v2/events/#{signal_node.id}/status/deciding_complete"

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      signal_children = signal_node.children

      expect(signal_children[0].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )
      expect(signal_children[1].reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
        .with(:body => activity_hash(signal_children.last, {current_server_status: :sent_to_client, current_client_status: :received}))
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::AsyncWorker.drain

      expect(signal_children[0].reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
      expect(signal_children[1].reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
    end
  end
end

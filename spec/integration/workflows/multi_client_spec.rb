require "spec_helper"
require "support/request_helper"
require "support/sidekiq_helper"

describe Backbeat, :api_test do
  include RequestHelper

  let(:client_A) { FactoryGirl.create(:user, name: "Client A") }
  let(:client_B) { FactoryGirl.create(:user, name: "Client B", activity_endpoint: 'http://client-a/activity') }
  let(:workflow) { FactoryGirl.create(:workflow, user: client_A) }

  def as_client(client)
    header("Client-Id", client.id)
    header("Authorization", "Token token=\"#{client.auth_token}\"")
    yield
  end

  context "workflow with multiple clients" do
    it "sends an activity created by client A to client B" do
      response = nil

      as_client(client_A) do
        response = post "workflows/#{workflow.id}/signal/test", options: {
          client_data: { method: 'publish', params: [1, 2, 3] },
          client_metadata: { metadata: '456'}
        }
      end

      expect(response.status).to eq(201)

      signal = JSON.parse(response.body)
      signal_node = workflow.children.where(id: signal['id']).first

      WebMock.stub_request(:post, client_A.decision_endpoint).with(
        body: decision_hash(signal_node, {
          current_server_status: :sent_to_client,
          current_client_status: :received
        })
      ).to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      as_client(client_A) do
        response = put "activities/#{signal_node.id}/status/processing"
      end

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "processing",
        "current_server_status" => "sent_to_client"
      )

      activity = {
        name: "Other client activity",
        client_id: client_B.id
      }

      as_client(client_A) do
        response = post "activities/#{signal_node.id}/decisions", { "decisions" => [activity] }
        response = put "activities/#{signal_node.id}/status/completed"
      end

      expect(signal_node.children.count).to eq(1)

      client_B_activity = signal_node.children.first

      WebMock.stub_request(:post, client_B.activity_endpoint).with(
        body: activity_hash(client_B_activity, {
          current_server_status: :sent_to_client,
          current_client_status: :received
        })
      ).to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      as_client(client_B) do
        response = put "activities/#{client_B_activity.id}/status/processing"
        response = put "activities/#{client_B_activity.id}/status/completed"
      end

      Backbeat::Workers::AsyncWorker.drain

      expect(client_B_activity.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )

      Backbeat::Workers::AsyncWorker.drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

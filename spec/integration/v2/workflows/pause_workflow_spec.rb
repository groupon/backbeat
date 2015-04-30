require 'spec_helper'
require "spec/helper/request_helper"
require "spec/helper/sidekiq_helper"

describe V2::Api, v2: true do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow, user: user) }

  before do
    header 'CLIENT_ID', user.id
  end

  context "Pause Workflow" do
    it "prevents all nodes from running until resumed" do
      response = post "v2/workflows/#{workflow.id}/signal/test", options: {
        client_data: { data: '123' },
        client_metadata: { metadata: '456'}
      }
      signal = JSON.parse(response.body)
      node = workflow.children.where(id: signal['id']).first

      expect(node.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "ready"
      )

      put "v2/workflows/#{workflow.id}/pause"

      V2::Workers::AsyncWorker.drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "ready",
        "current_server_status" => "paused"
      )

      response = put "v2/workflows/#{workflow.id}/resume"

      expect(response.status).to eq(200)

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => decision_hash(node))
        .to_return(:status => 200, :body => "", :headers => {})

      allow(V2::Client).to receive(:perform_action)

      SidekiqHelper.soft_drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "received",
        "current_server_status" => "sent_to_client"
      )
    end
  end
end


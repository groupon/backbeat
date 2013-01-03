require 'spec_helper'
require 'helper/request_helper'
require 'helper/sidekiq_helper'

describe Backbeat, :api_test do
  include RequestHelper

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }
  let(:node) { FactoryGirl.create(:node, user: user, workflow: workflow, current_client_status: :received, current_server_status: :sent_to_client) }
  let(:workflow_to_link) { FactoryGirl.create(:workflow, user: user, subject: {test: :node}) }

  context "linked" do
    it "forces a node to wait to complete until its links complete" do
      response = post "v2/workflows/#{workflow_to_link.id}/signal/test", { options: { parent_link_id: node.id } }

      signal_node = workflow_to_link.nodes.first

      expect(workflow_to_link.nodes.count).to eq(1)
      expect(signal_node.parent_link).to eq(node)
      expect(node.child_links).to eq([signal_node])

      put "v2/events/#{node.id}/status/completed"

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
       .with(:body => decision_hash(signal_node, {current_server_status: :sent_to_client, current_client_status: :received}))
       .to_return(:status => 200, :body => "", :headers => {})

      Backbeat::Workers::AsyncWorker.drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      put "v2/events/#{signal_node.id}/status/completed"

      SidekiqHelper.soft_drain

      expect(signal_node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )

      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "processing_children"
      )

      SidekiqHelper.soft_drain

      expect(node.reload.attributes).to include(
        "current_client_status" => "complete",
        "current_server_status" => "complete"
      )
    end
  end
end

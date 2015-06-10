require 'spec_helper'
require 'helper/request_helper'

describe Backbeat::Web::EventsApi do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow_with_node, user: user) }
  let(:node) { workflow.children.first }


  before do
    header 'CLIENT_ID', user.id
    Backbeat::Client.stub(:make_decision)
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "PUT /events/:id/restart" do
    context "with valid restart state" do
      before do
        node.update_attributes(
          current_client_status: :errored,
          current_server_status: :errored
        )
        WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
          .with(:body => activity_hash(node, {current_server_status: :sent_to_client, current_client_status: :received}))
          .to_return(:status => 200, :body => "", :headers => {})
      end

      it "returns 200" do
        response = put "v2/events/#{node.id}/restart"
        expect(response.status).to eq(200)
      end

      it "restarts the node" do
        response = put "v2/events/#{node.id}/restart"

        Backbeat::Workers::AsyncWorker.drain

        expect(node.reload.current_client_status).to eq("received")
        expect(node.reload.current_server_status).to eq("sent_to_client")
      end
    end

    context "with invalid restart state" do
      it "returns 409" do
        response = put "v2/events/#{node.id}/restart"
        expect(response.status).to eq(409)
      end
    end

    context "when no node found for id" do
      it "returns a 404" do
        response = put "v2/events/#{SecureRandom.uuid}/restart"
        expect(response.status).to eq(404)
      end
    end
  end

  context "POST /events/:id/decisions" do
    it "creates the node detail with retry data" do
      parent_node = workflow.children.first

      activity = FactoryGirl.build(:client_activity_post_to_decision).merge(
        retry: 20,
        retry_interval: 50
      )
      activity_to_post = { "args" => { "decisions" => [activity] }}
      post "v2/events/#{parent_node.id}/decisions", activity_to_post
      activity_node = parent_node.children.first

      expect(activity_node.node_detail.retry_interval).to eq(50)
      expect(activity_node.node_detail.retries_remaining).to eq(20)
      expect(activity_node.client_metadata).to eq({"version"=>"v2"})
      expect(activity_node.client_data).to eq({"could"=>"be", "any"=>"thing"})
    end
  end

  context "GET /events/:id" do
    it "returns the node data" do
      node = workflow.children.first
      response = get "v2/workflows/#{workflow.id}/events/#{node.id}"
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(node.id)
    end

    it "returns 404 if the node does not belong to the user" do
      node = FactoryGirl.create(
        :workflow_with_node,
        user: FactoryGirl.create(:user)
      ).children.first

      response = get "v2/workflows/#{node.workflow_id}/events/#{node.id}"

      expect(response.status).to eq(404)
    end

    it "finds the node by id when no workflow id is provided" do
      node = workflow.children.first
      response = get "v2/events/#{node.id}"
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(node.id)
    end

    it "returns 404 if the node does not belong to the workflow" do
      node = FactoryGirl.create(
        :workflow_with_node,
        name: :a_unique_name,
        user: workflow.user
      ).children.first

      response = get "v2/workflows/#{workflow.id}/events/#{node.id}"

      expect(response.status).to eq(404)
    end
  end

  context "PUT /events/:id/status/deactivated" do
    it "fires the DeactivateNode event" do
      second_node = FactoryGirl.create(
        :node,
        workflow: workflow,
        parent: node,
        user: user
      )

      put "v2/events/#{second_node.id}/status/deactivated"

      expect(node.reload.current_server_status).to eq("deactivated")
    end
  end

  context "PUT /events/:id/status/processing" do
    it "fires the ClientProcessing event" do
      node.update_attributes(current_client_status: :received)
      put "v2/events/#{node.id}/status/processing"

      expect(node.reload.current_client_status).to eq("processing")
    end

    it "returns an error with an invalid state change" do
      node.update_attributes(current_client_status: :processing)
      response = put "v2/events/#{node.id}/status/processing"
      body = JSON.parse(response.body)

      expect(response.status).to eq(409)
      expect(body["error"]).to eq("Cannot transition current_client_status from processing to processing")
      expect(body["currentStatus"]).to eq("processing")
      expect(body["attemptedStatus"]).to eq("processing")
    end

    it "does not mark the node in error state with invalid client state change" do
      node.update_attributes(current_client_status: :processing, current_server_status: :sent_to_client)
      response = put "v2/events/#{node.id}/status/processing"
      expect(node.reload.current_client_status).to eq("processing")
      expect(node.reload.current_server_status).to eq("sent_to_client")
    end

    it "does not mark the node in error state with invalid client state change" do
      node.update_attributes(current_client_status: :processing, current_server_status: :sent_to_client)
      response = put "v2/events/#{node.id}/status/processing"
      expect(node.reload.current_client_status).to eq("processing")
      expect(node.reload.current_server_status).to eq("sent_to_client")
    end
  end

  context "PUT /events/:id/status/errored" do
    it "stores the client backtrace in the client node detail" do
      client_params = { "error" => { "backtrace" => "The backtrace" }}
      put "v2/events/#{node.id}/status/errored", { "args" => client_params }
      expect(node.client_node_detail.result).to eq(client_params)
    end
  end

  context "PUT /events/:id/reset" do
    it "deactivates all child nodes on the node" do
      child = FactoryGirl.create(:node, user: user, workflow: workflow, parent: node)

      put "v2/events/#{node.id}/reset"

      expect(node.children.count).to eq(1)
      expect(child.reload.current_server_status).to eq("deactivated")
    end
  end
end

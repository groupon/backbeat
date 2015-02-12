require 'spec_helper'
require 'spec/helper/request_helper'

describe V2::Api, v2: true do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }


  before do
    header 'CLIENT_ID', user.uuid
    WorkflowServer::Client.stub(:make_decision)
    WebMock.stub_request(:post, "http://backbeat-client:9000/notifications")
  end

  context "POST /workflows" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post 'v2/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}

      expect(response.status).to eq(201)

      json_response = JSON.parse(response.body)
      wf_in_db = V2::Workflow.find(json_response['id'])

      expect(wf_in_db).to_not be_nil
      expect(wf_in_db.subject).to eq({"subject_klass" => "PaymentTerm", "subject_id" => "100"})

      response = post 'v2/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}
      expect(json_response['id']).to eq(JSON.parse(response.body)['id'])
    end
  end

  context "GET /workflow/:id" do
    it "returns a workflow given an id" do
      response = get "v2/workflows/#{workflow.id}"
      expect(response.status).to eq(200)
      json_response = JSON.parse(response.body)

      expect(json_response["id"]).to eq(workflow.id)
    end
  end

  context "GET /workflow/:id/children" do
    it "returns the workflows immediate" do
      second_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: workflow,
        user: user
      )

      response = get "v2/workflows/#{workflow.id}/children"
      expect(response.status).to eq(200)

      json_response = JSON.parse(response.body)
      children = workflow.children

      expect(json_response.first["id"]).to eq(children.first.id)
      expect(json_response.second["currentServerStatus"]).to eq(children.second.current_server_status)
      expect(json_response.count).to eq(2)
    end
  end

  context "PUT /events/:id/restart" do
    context "with valid restart state" do
      before do
        node.update_attributes(
          current_client_status: :errored,
          current_server_status: :errored
        )
        WebMock.stub_request(:post, "http://backbeat-client:9000/activity")
          .with(:body => activity_hash(node).to_json)
          .to_return(:status => 200, :body => "", :headers => {})

      end

      it "returns 200" do
        response = put "v2/events/#{node.id}/restart"
        expect(response.status).to eq(200)
      end

      it "restarts the node" do
        response = put "v2/events/#{node.id}/restart"

        V2::Workers::AsyncWorker.drain

        expect(node.reload.current_client_status).to eq("received")
        expect(node.reload.current_server_status).to eq("sent_to_client")
      end
    end

    context "with invalid restart state" do
      it "returns 400" do
        response = put "v2/events/#{node.id}/restart"
        expect(response.status).to eq(400)
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
        :v2_workflow_with_node,
        user: FactoryGirl.create(:v2_user)
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
        :v2_workflow_with_node,
        user: user
      ).children.first

      response = get "v2/workflows/#{workflow.id}/events/#{node.id}"

      expect(response.status).to eq(404)
    end
  end

  context "PUT /workflows/:id/deactivated" do
    it "fires the DeactivateNode event" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::DeactivateNode, workflow)

      put "v2/workflows/#{workflow.id}/deactivated"
    end
  end

  context "PUT /events/:id/status/deactivated" do
    it "fires the DeactivateNode event" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::DeactivateNode, node)

      put "v2/events/#{node.id}/status/deactivated"
    end
  end

  context "GET /workflows/:id/tree" do
    it "returns the workflow tree as a hash" do
      response = get "v2/workflows/#{workflow.id}/tree"
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(workflow.uuid)
    end
  end

  context "GET /workflows/:id/tree/print" do
    it "returns the workflow tree as a string" do
      response = get "v2/workflows/#{workflow.id}/tree/print"
      body = JSON.parse(response.body)

      expect(body["print"]).to include(workflow.name)
    end
  end
end

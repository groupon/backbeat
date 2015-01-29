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

  before do
    header 'CLIENT_ID', user.uuid
    WorkflowServer::Client.stub(:make_decision)
  end

  context "POST /workflows" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post '/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}

      expect(response.status).to eq(201)

      json_response = JSON.parse(response.body)
      wf_in_db = V2::Workflow.find(json_response['id'])

      expect(wf_in_db).to_not be_nil
      expect(wf_in_db.subject).to eq({"subject_klass" => "PaymentTerm", "subject_id" => "100"})

      response = post '/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}
      expect(json_response['id']).to eq(JSON.parse(response.body)['id'])
    end
  end

  context "PUT :id/restart" do
    let(:node) { workflow.children.first }

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
        response = put "events/#{node.id}/restart"
        expect(response.status).to eq(200)
      end

      it "restarts the node" do
        response = put "events/#{node.id}/restart"

        V2::Workers::AsyncWorker.drain

        expect(node.reload.current_client_status).to eq("received")
        expect(node.reload.current_server_status).to eq("sent_to_client")
      end
    end

    context "with invalid restart state" do
      it "returns 400" do
        response = put "events/#{node.id}/restart"
        expect(response.status).to eq(400)
      end
    end

    context "when no node found for id" do
      it "returns a 404" do
        response = put "events/#{SecureRandom.uuid}/restart"
        expect(response.status).to eq(404)
      end
    end
  end

  context "POST /:id/decisions" do
    it "creates the node detail with retry data" do
      parent_node = workflow.children.first

      activity = FactoryGirl.build(:client_activity_post_to_decision).merge(
        retry: 20,
        retry_interval: 50
      )
      activity_to_post = { "args" => { "decisions" => [activity] }}
      post "events/#{parent_node.id}/decisions", activity_to_post
      activity_node = parent_node.children.first

      expect(activity_node.node_detail.retry_interval).to eq(50)
      expect(activity_node.node_detail.retries_remaining).to eq(20)
    end
  end

  context "GET /workflows/:id/tree" do
    it "returns the workflow tree as a hash" do
      response = get "workflows/#{workflow.id}/tree"
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(workflow.id)
    end
  end

  context "GET /workflows/:id/tree/print" do
    it "returns the workflow tree as a string" do
      response = get "workflows/#{workflow.id}/tree/print"
      body = JSON.parse(response.body)

      expect(body["print"]).to include(workflow.name)
    end
  end
end

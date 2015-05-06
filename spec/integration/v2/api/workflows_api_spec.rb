require 'spec_helper'
require 'spec/helper/request_helper'

describe V2::Api::WorkflowsApi, v2: true do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:v2_user) }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  before do
    header 'CLIENT_ID', user.id
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

  context "POST /workflows/:id/signal/:name" do
    let(:signal_params) {{
      options: {
        client_data: { data: '123' },
        metadata: { metadata: '456'}
      }
    }}

    it "calls schedule next node after creating the signal" do
      expect(V2::Server).to receive(:fire_event).with(V2::Events::ScheduleNextNode, workflow)
      response = post "v2/workflows/#{workflow.id}/signal/new_signal", signal_params
    end

    it "creates a signal on the workflow" do
      response = post "v2/workflows/#{workflow.id}/signal/new_signal", signal_params

      expect(response.status).to eq(201)
      expect(workflow.children.count).to eq(2)
    end

    it "adds node nad calls schedule next node on the workflow" do
      response = post "v2/workflows/#{workflow.id}/signal/test", signal_params

      expect(workflow.nodes.last.client_data).to eq({ 'data' => '123' })
      expect(workflow.nodes.last.client_metadata).to eq({ 'metadata' => '456' })
    end

    it "returns a 400 response if the workflow is complete" do
      workflow.complete!
      expect(workflow.children.count).to eq(1)

      response = post "v2/workflows/#{workflow.id}/signal/new_signal", signal_params

      expect(response.status).to eq(400)
      expect(workflow.children.count).to eq(1)
    end
  end

  context "GET /workflows/:id" do
    it "returns a workflow given an id" do
      response = get "v2/workflows/#{workflow.id}"
      expect(response.status).to eq(200)
      json_response = JSON.parse(response.body)

      expect(json_response["id"]).to eq(workflow.id)
    end
  end

  context "GET /workflows/:id/children" do
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

  context "GET /workflows/:id/nodes" do
    before do
      second_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: workflow,
        user: user
      )
      @third_node = FactoryGirl.create(
        :v2_node,
        workflow: workflow,
        parent: second_node,
        user: user,
        current_server_status: :complete
      )
      @third_node.client_node_detail.update_attributes!(metadata: {"version"=>"v2", "workflow_type_on_v2"=>true})
    end

    it "returns the workflows nodes in ClientNodeSerializer" do
      response = get "v2/workflows/#{workflow.id}/nodes"
      expect(response.status).to eq(200)

      json_response = JSON.parse(response.body)
      nodes = workflow.nodes

      expect(json_response.first["id"]).to eq(nodes.first.id)
      expect(json_response.second["id"]).to eq(nodes.second.id)
      expect(json_response.third["id"]).to eq(nodes.third.id)
      expect(json_response.third["currentServerStatus"]).to eq(nodes.third.current_server_status)
      expect(json_response.third["metadata"]).to eq({"version"=>"v2", "workflowTypeOnV2"=>true})
      expect(json_response.count).to eq(3)
    end

    it "returns nodes limited by query" do
      response = get "v2/workflows/#{workflow.id}/nodes?currentServerStatus=complete"
      expect(response.status).to eq(200)

      json_response = JSON.parse(response.body)
      expect(json_response.first["id"]).to eq(@third_node.id)
      expect(json_response.count).to eq(1)
    end
  end

  context "GET /workflows/:id/tree" do
    it "returns the workflow tree as a hash" do
      response = get "v2/workflows/#{workflow.id}/tree"
      body = JSON.parse(response.body)

      expect(body["id"]).to eq(workflow.id.to_s)
    end
  end

  context "GET /workflows/:id/tree/print" do
    it "returns the workflow tree as a string" do
      response = get "v2/workflows/#{workflow.id}/tree/print"
      body = JSON.parse(response.body)

      expect(body["print"]).to include(workflow.name)
    end
  end

  context "PUT /workflows/:id/complete" do
    it "marks the workflow as complete" do
      response = put "v2/workflows/#{workflow.id}/complete"

      expect(response.status).to eq(200)
      expect(workflow.reload.complete?).to eq(true)
    end
  end

  context "GET /workflows" do
    let(:query) {{
      decider: workflow.decider,
      subject: workflow.subject.to_json,
      workflow_type: workflow.name
    }}

    it "returns the first workflow matching the decider and subject" do
      workflow.update_attributes(migrated: true)

      response = get "v2/workflows", query
      body = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(body["id"]).to eq(workflow.id)
    end

    [:decider, :subject, :workflow_type].each do |param|
      it "returns 404 if a workflow is not found by #{param}" do
        workflow.update_attributes(migrated: true)

        response = get "v2/workflows", query.merge(param => "Foo")

        expect(response.status).to eq(404)
      end
    end

    it "returns 404 if the workflow is not fully migrated" do
      workflow.update_attributes(migrated: false)

      response = get "v2/workflows", query

      expect(response.status).to eq(404)
    end
  end
end

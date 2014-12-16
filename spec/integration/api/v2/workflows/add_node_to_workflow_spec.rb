require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  deploy BACKBEAT_APP

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user)  }
  let(:v2_user) {FactoryGirl.create(:v2_user)}
  let(:v2_workflow) {FactoryGirl.create(:v2_workflow)}

  before do
    header 'CLIENT_ID', user.id
    v2_user
    v2_workflow
  end

  context "POST /workflows/:id/signal" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post "/workflows/#{v2_workflow.id}/signal/test", options: { client_data: {data: '123'}, client_metadata: {metadata: '456'} }

      WorkflowServer::Workers::SidekiqJobWorker.drain

      response.status.should == 201
      signal = JSON.parse(response.body)
      v2_workflow.reload
      node = v2_workflow.nodes.where(id: signal['id']).first
      node.attributes.should include(
        "current_client_status" => "pending",
        "current_server_status" => "pending",
        "mode" => "blocking",
        "name" => "test",
        "user_id" => v2_user.id,
        "workflow_id" => v2_workflow.id)
      node.client_node_detail.data.should == {'data' => '123'}
      node.client_node_detail.metadata.should == {'metadata' => '456'}
      node.node_detail.retry_times_remaining.should == 4
      node.node_detail.retry_interval.should == 20
    end
  end
end

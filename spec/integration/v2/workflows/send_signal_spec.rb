require 'spec_helper'

describe Api::Workflows, v2: true do
  include Rack::Test::Methods

  deploy BACKBEAT_APP

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user)  }
  let(:v2_user) { FactoryGirl.create(:v2_user) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow) }

  before do
    header 'CLIENT_ID', user.id
    v2_user
    v2_workflow
    RSpec::Mocks.proxy_for( WorkflowServer::Client).reset
  end

  context "POST /workflows/:id/signal" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post "/workflows/#{v2_workflow.id}/signal/test", options: { client_data: {data: '123'}, client_metadata: {metadata: '456'} }
      response.status.should == 201
      signal = JSON.parse(response.body)
      node = v2_workflow.nodes.where(id: signal['id']).first
      node.attributes.should include( "current_client_status" => "ready",
                                     "current_server_status" => "ready")

      decision_to_make = FactoryGirl.build(:client_decision,
                                           id: node.id,
                                           name: :test,
                                           parentId: node.parent_id,
                                           userId: node.user_id,
                                           decider: v2_workflow.decider,
                                           subject: v2_workflow.subject)

      WebMock.stub_request(:post, "http://backbeat-client:9000/decision")
        .with(:body => {decision: decision_to_make}.to_json,
              :headers => {'Content-Length'=>'222', 'content-type'=>'application/json'})
        .to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::SidekiqWorker.drain
      node.reload.attributes.should include( "current_client_status" => "received",
                                            "current_server_status" => "sent_to_client")

      response = put "/events/#{node.id}/status/deciding"
      node.reload.attributes.should include( "current_client_status" => "processing",
                                            "current_server_status" => "sent_to_client")

      activity= FactoryGirl.build(:client_activity_post_to_decision)

      activity_to_post = { "args" => {"decisions" => [activity]}}

      response = post "events/#{node.id}/decisions", activity_to_post
      node.reload.attributes.should include( "current_client_status" => "processing",
                                            "current_server_status" => "sent_to_client")
      node.reload.children.count.should == 1

      response = put "/events/#{node.id}/status/deciding_complete"
      node.reload.attributes.should include( "current_client_status" => "complete",
                                            "current_server_status" => "processing_children")


      activity_node = node.children.first
      activity_node.reload.attributes.should include( "current_client_status" => "ready",
                                                     "current_server_status" => "ready")

      activity_hash =  {"activity" => { "id" => activity_node.id,
                                        "mode" => "blocking",
                                        "name" => activity_node.name,
                                        "parentId" => activity_node.parent_id,
                                        "workflowId" => activity_node.workflow_id,
                                        "userId" => activity_node.user_id,
                                        "clientData" => {"could" => "be","any" => "thing"}}}

      WebMock.stub_request(:post, "http://backbeat-client:9000/activity").
        with(:body => activity_hash.to_json,
             :headers => {'Content-Length'=>'284', 'Content-Type'=>'application/json'}).
        to_return(:status => 200, :body => "", :headers => {})


      V2::Workers::SidekiqWorker.drain
      activity_node.reload.attributes.should include( "current_client_status" => "received",
                                                     "current_server_status" => "sent_to_client")

      response = put "/events/#{activity_node.id}/status/completed"
      activity_node.reload.attributes.should include( "current_client_status" => "complete",
                                                     "current_server_status" => "processing_children")

      V2::Workers::SidekiqWorker.drain
      activity_node.reload.attributes.should include( "current_client_status" => "complete",
                                                     "current_server_status" => "complete")

      node.reload.attributes.should include( "current_client_status" => "complete",
                                            "current_server_status" => "complete")
    end
  end
end

require 'spec_helper'

describe Api::Workflows, v2: true do
  include Rack::Test::Methods

  deploy BACKBEAT_APP

  def app
    FullRackApp
  end

  let(:v2_user) { FactoryGirl.create(:v2_user) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow_with_node_running, user: v2_user) }
  let(:activity_node) { v2_workflow.nodes.where("parent_id IS NOT NULL").first }

  before do
    header 'CLIENT_ID', v2_user.id
    RSpec::Mocks.proxy_for( WorkflowServer::Client).reset
  end

  context "client connection timeout" do

  end

  context "client error" do
    it "retries with backoff and then succeeds" do
      activity_node.reload.attributes.should include("current_client_status" => "received",
                                                     "current_server_status" => "sent_to_client")
      activity_node.node_detail.retry_times_remaining.should == 4

      response = put "/events/#{activity_node.id}/status/errored"
      activity_node.reload.attributes.should include("current_client_status" => "errored",
                                                     "current_server_status" => "retrying")

      activity_hash =  {"activity" => { "id" => activity_node.id,
                                        "mode" => "blocking",
                                        "name" => activity_node.name,
                                        "parentId" => activity_node.parent_id,
                                        "workflowId" => activity_node.workflow_id,
                                        "userId" => activity_node.user_id,
                                        "clientData" => {"could" => "be","any" => "thing"}}}
      WebMock.stub_request(:post, "http://backbeat-client:9000/activity").
        with(:body => activity_hash.to_json,
             :headers => {'Content-Length'=>'287', 'Content-Type'=>'application/json'}).
        to_return(:status => 200, :body => "", :headers => {})

      V2::Workers::SidekiqWorker.drain

      activity_node.reload.attributes.should include("current_client_status" => "received",
                                                     "current_server_status" => "sent_to_client")
      activity_node.node_detail.retry_times_remaining.should == 3

      response = put "/events/#{activity_node.id}/status/completed"
      activity_node.reload.attributes.should include("current_client_status" => "complete",
                                                     "current_server_status" => "processing_children")

      V2::Workers::SidekiqWorker.drain
      activity_node.reload.attributes.should include("current_client_status" => "complete",
                                                     "current_server_status" => "complete")

      activity_node.parent.attributes.should include("current_client_status" => "complete",
                                                     "current_server_status" => "complete")
    end

    it "retries full number of retries available and fails" do
    end
  end
end


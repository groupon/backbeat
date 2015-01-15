require 'spec_helper'
require 'webmock/rspec'

describe WorkflowServer::Client, v2: true do
  context "#notify_of" do

    let(:user) { FactoryGirl.create(:v2_user, notification_endpoint: "http://notifications.com/api/v1/workflows/notify_of") }
    let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }

    it "calls the notify of endpoint" do
      node = workflow.nodes.first
      error = {"couldbe" => "anything"}
      notification_body = WorkflowServer::Helper::HashKeyTransformations.camelize_keys(
        {
          "notification" => {
            "type" =>"V2::Node",
            "id"=> node.id,
            "name" => node.name,
            "subject" => node.workflow.subject,
            "message" => "error",
            "error" => error
          }
        }
      )
      WebMock.stub_request(:post, "http://notifications.com/api/v1/workflows/notify_of")
        .with(body: notification_body.to_json)
        .to_return(status: 200, body: "", headers: {})

      V2::Client.notify_of(node, "error", error)

      expect(WebMock).to have_requested(
        :post, "http://notifications.com/api/v1/workflows/notify_of"
      ).with(body: notification_body.to_json)
    end

    it "raises an http error unless response is between 200-299" do
      node = workflow.nodes.first
      WebMock.stub_request(:post, "http://notifications.com/api/v1/workflows/notify_of").to_return(status: 404)
      expect {
        V2::Client.notify_of(node, "error", nil)
      }.to raise_error(WorkflowServer::HttpError, "http request to notify_of failed")
    end
  end
end

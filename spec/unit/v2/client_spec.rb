require 'spec_helper'
require 'webmock/rspec'

describe V2::Client, v2: true do

  let(:user) { FactoryGirl.create(:v2_user, notification_endpoint: "http://notifications.com/api/v1/workflows/notify_of") }
  let(:workflow) { FactoryGirl.create(:v2_workflow_with_node, user: user) }
  let(:node) { workflow.children.first }

  context "#notify_of" do
    it "calls the notify of endpoint" do
      error = {"couldbe" => "anything"}
      notification_body = WorkflowServer::Helper::HashKeyTransformations.camelize_keys(
        {
          "notification" => {
            "type" =>"V2::Node",
            "id"=> node.id,
            "name" => node.name,
            "subject" => node.subject,
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
      WebMock.stub_request(:post, "http://notifications.com/api/v1/workflows/notify_of").to_return(status: 404)
      expect {
        V2::Client.notify_of(node, "error", nil)
      }.to raise_error(WorkflowServer::HttpError, "http request to notify_of failed")
    end
  end

  context "perform_action" do
    it "sends a call to make decision if the node is a legacy signal" do
      node.node_detail.legacy_type = 'signal'
      expect(WorkflowServer::Client).to receive(:make_decision)
      V2::Client.perform_action(node)
    end

    it "sends a call to perform activity if the node is a legacy activity" do
      node.node_detail.legacy_type = 'activity'
      expect(WorkflowServer::Client).to receive(:perform_activity)
      V2::Client.perform_action(node)
    end
  end
end

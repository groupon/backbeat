require 'spec_helper'
require 'webmock/rspec'

describe WorkflowServer::Async::Client do
  before do
    WorkflowServer::Async::Client.stub!(:make_decision)
    WorkflowServer::Async::Client.stub(:notify_of)
    WorkflowServer::Async::Client.stub(:perform_activity)
  end
  let(:user) { FactoryGirl.create(:user,
                                   decision_callback_endpoint: "http://decisions.com/api/v1/workflows/make_decision",
                                   activity_callback_endpoint: "http://activity.com/api/v1/workflows/perform_activity",
                                   notification_endpoint:      "http://notifications.com/api/v1/workflows/notify_of") }

  context "#make_decisions" do
    it "calls the make decision endpoint" do
      decision = FactoryGirl.create(:decision, workflow: FactoryGirl.create(:workflow, user: user))
      WorkflowServer::Async::Client.unstub!(:make_decision)
      WebMock.stub_request(:post, "http://decisions.com/api/v1/workflows/make_decision").with(:body => {decision: WorkflowServer::Helper::HashKeyTransformations.camelize_keys(decision.serializable_hash)}.to_json, :headers => {'Content-Length'=>'381', 'Content-Type'=>'application/json'} )
      WorkflowServer::Async::Client.make_decision(decision)

      WebMock.should have_requested(:post, "http://decisions.com/api/v1/workflows/make_decision").with(:body => {decision: WorkflowServer::Helper::HashKeyTransformations.camelize_keys(decision.serializable_hash)}.to_json, :headers => {'Content-Length'=>'381', 'Content-Type'=>'application/json'} )
    end

    it "raises an http error unless response is between 200-299" do
      decision = FactoryGirl.create(:decision, workflow: FactoryGirl.create(:workflow, user: user))
      WorkflowServer::Async::Client.unstub!(:make_decision)
      WebMock.stub_request(:post, "http://decisions.com/api/v1/workflows/make_decision").to_return(status: 404)
      expect {
        WorkflowServer::Async::Client.make_decision(decision)
      }.to raise_error(WorkflowServer::HttpError, "http request to make_decision failed")
    end
  end

  context "#perform_activity" do
    it "calls the perform activity endpoint" do
      activity = FactoryGirl.create(:activity, workflow: FactoryGirl.create(:workflow, user: user))
      WorkflowServer::Async::Client.unstub!(:perform_activity)
      WebMock.stub_request(:post, "http://activity.com/api/v1/workflows/perform_activity").with(:body => {activity: WorkflowServer::Helper::HashKeyTransformations.camelize_keys(activity.serializable_hash)}.to_json, :headers => {'Content-Length'=>'526', 'Content-Type'=>'application/json'} )
      WorkflowServer::Async::Client.perform_activity(activity)

      WebMock.should have_requested(:post, "http://activity.com/api/v1/workflows/perform_activity").with(:body => {activity: WorkflowServer::Helper::HashKeyTransformations.camelize_keys(activity.serializable_hash)}.to_json, :headers => {'Content-Length'=>'526', 'Content-Type'=>'application/json'} )
    end

    it "raises an http error unless response is between 200-299" do
      activity = FactoryGirl.create(:activity, workflow: FactoryGirl.create(:workflow, user: user))
      WorkflowServer::Async::Client.unstub!(:perform_activity)
      WebMock.stub_request(:post, "http://activity.com/api/v1/workflows/perform_activity").to_return(status: 404)
      expect {
        WorkflowServer::Async::Client.perform_activity(activity)
      }.to raise_error(WorkflowServer::HttpError, "http request to perform_activity failed")
    end
  end

  context "#notify_of" do
    it "calls the perform activity endpoint" do
      activity = FactoryGirl.create(:activity, workflow: FactoryGirl.create(:workflow, user: user))
      WorkflowServer::Async::Client.unstub!(:notify_of)
      WebMock.stub_request(:post, "http://notifications.com/api/v1/workflows/notify_of").
               with(:body => "{\"notification\":\"PaymentTerm(100):activity(#{activity.name}):start\"}",
                    :headers => {'Content-Length'=>'72', 'Content-Type'=>'application/json'}).
               to_return(:status => 200, :body => "", :headers => {})
      WorkflowServer::Async::Client.notify_of(activity, :start)

      WebMock.should have_requested(:post, "http://notifications.com/api/v1/workflows/notify_of").
               with(:body => "{\"notification\":\"PaymentTerm(100):activity(#{activity.name}):start\"}",
                    :headers => {'Content-Length'=>'72', 'Content-Type'=>'application/json'})
    end
  end
end

require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
    WorkflowServer::Client.stub(:make_decision)
  end

  context "PUT /workflows/:id/events/:event_id/status/completed" do
    it "branches cannot complete without next decision" do
      decision = FactoryGirl.create(:decision)
      branch = FactoryGirl.create(:branch, status: :executing, parent: decision, workflow: decision.workflow)
      wf = branch.workflow
      user = wf.user
      response = put "/workflows/#{wf.id}/events/#{branch.id}/status/completed"
      response.status.should == 400
      branch.reload
      json_response = JSON.parse(response.body)
      json_response['error'].should == "branch:automate_payment? has to make a decision or return none."
      branch.status.should_not == :complete
    end
  end
end
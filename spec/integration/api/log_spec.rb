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

  it "includes the transaction id in the response" do
    wf = FactoryGirl.create(:workflow)
    get "/workflows/#{wf.id}"
    last_response.status.should == 200
    last_response.headers.keys.should include("X-backbeat-tid")
  end
end
require 'spec_helper'

describe Api::Authenticate do
  before do
    @env = {}
    @mock_app = lambda { |env|
      @env.merge!(env)
      [200, {'Content-Type' => 'application/json'}, "[]"]
    }
  end

  it "returns 401 if client_id header is missing" do
    request = Rack::MockRequest.new(Api::Authenticate.new(@mock_app))
    response = request.post("/some_place")
    response.should_not be_nil
    response.status.should == 401
    response.headers["Content-Type"].should == "text/plain"
    response.body.should == 'Unauthorized'
    @env.should be_empty
  end

  it "returns 401 if client_id header is incorrect" do
    request = Rack::MockRequest.new(Api::Authenticate.new(@mock_app))
    response = request.post("/some_place", {"HTTP_CLIENT_ID" => "XX_TT"})
    response.should_not be_nil
    response.status.should == 401
    response.headers["Content-Type"].should == "text/plain"
    response.body.should == 'Unauthorized'
    @env.should be_empty
  end

  it "calls the application with the user set in the environment" do
    user = FactoryGirl.create(:user)
    request = Rack::MockRequest.new(Api::Authenticate.new(@mock_app))
    response = request.post("/some_place", {"HTTP_CLIENT_ID" => user.id})
    response.should_not be_nil
    response.status.should == 200
    response.headers["Content-Type"].should == "application/json"
    response.body.should == "[]"
    @env['WORKFLOW_CURRENT_USER'].should_not be_nil
    @env['WORKFLOW_CURRENT_USER'].should == user
  end
end
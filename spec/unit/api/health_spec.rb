require 'spec_helper'

describe Api::Health do
  before do
    @env = {}
    @mock_app = lambda { |env|
      @env['APP_WAS_CALLED'] = true
      [200, {'Content-Type' => 'text/plain'}, "hello from app"]
    }
  end

  it "doesn't handle the request if PATH INFO is not /health" do
    request = Rack::MockRequest.new(Api::Health.new(@mock_app))
    response = request.post("/some_place")
    @env.keys.should include("APP_WAS_CALLED")
    @env["APP_WAS_CALLED"].should == true
    response.body.should == "hello from app"
  end

  it "doesn't call the app if PATH INFO is /health" do
    request = Rack::MockRequest.new(Api::Health.new(@mock_app))
    response = request.post("/health")
    @env.keys.should_not include("APP_WAS_CALLED")
    response.status.should == 200
  end
end
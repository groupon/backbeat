require 'spec_helper'

describe Api::Middleware::Authenticate, v2: true do
  before do
    @env = {}
    @mock_app = lambda { |env|
      @env.merge!(env)
      [200, {'Content-Type' => 'application/json'}, "[]"]
    }
  end

  it "looks up the user by v2 api version" do
    user = FactoryGirl.create(:v2_user)
    request = Rack::MockRequest.new(Api::Middleware::Authenticate.new(@mock_app))
    response = request.post("/v2/workflows", {"HTTP_CLIENT_ID" => user.id})
    expect(response.status).to eq(200)
    expect(@env['WORKFLOW_CURRENT_USER']).to eq(user)
  end
end

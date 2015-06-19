require 'spec_helper'

describe Backbeat::Web::Middleware::Authenticate do
  before do
    @env = {}
    @mock_app = lambda { |env|
      @env.merge!(env)
      [200, {'Content-Type' => 'application/json'}, "[]"]
    }
  end

  it "returns 401 if client_id header is missing" do
    request = Rack::MockRequest.new(described_class.new(@mock_app))
    response = request.post("/some_place")
    expect(response).not_to be_nil
    expect(response.status).to eq(401)
    expect(response.headers["Content-Type"]).to eq("text/plain")
    expect(response.body).to eq('Unauthorized')
    expect(@env).to be_empty
  end

  it "returns 401 if client_id header is incorrect" do
    request = Rack::MockRequest.new(described_class.new(@mock_app))
    response = request.post("/some_place", {"HTTP_CLIENT_ID" => "XX_TT"})
    expect(response).not_to be_nil
    expect(response.status).to eq(401)
    expect(response.headers["Content-Type"]).to eq("text/plain")
    expect(response.body).to eq('Unauthorized')
    expect(@env).to be_empty
  end

  it "calls the application with the user set in the environment" do
    user = FactoryGirl.create(:user)
    request = Rack::MockRequest.new(described_class.new(@mock_app))
    response = request.post("/some_place", {"HTTP_CLIENT_ID" => user.id})
    expect(response).not_to be_nil
    expect(response.status).to eq(200)
    expect(response.headers["Content-Type"]).to eq("application/json")
    expect(response.body).to eq("[]")
    expect(@env['WORKFLOW_CURRENT_USER']).not_to be_nil
    expect(@env['WORKFLOW_CURRENT_USER']).to eq(user)
  end
end

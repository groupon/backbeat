require 'spec_helper'

describe Backbeat::Web::API, :api_test do
  it "returns 401 if client id header is missing" do
    response = get "/v2/debug/error_workflows"

    expect(response.status).to eq(401)
    expect(JSON.parse(response.body)).to eq({ 'error' => 'Unauthorized' })
  end

  it "returns 401 if client id header is incorrect" do
    header "CLIENT_ID", "XX_TT"
    response = get "/v2/debug/error_workflows"

    expect(response.status).to eq(401)
    expect(JSON.parse(response.body)).to eq({ 'error' => 'Unauthorized' })
  end

  it "calls the app if the client id is provided" do
    user = FactoryGirl.create(:user)
    header "CLIENT_ID", user.id
    response = get "/v2/debug/error_workflows"

    expect(response.status).to eq(200)
  end
end

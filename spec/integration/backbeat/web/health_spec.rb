require 'spec_helper'

describe Backbeat::Web::Middleware::Health, :api_test do

  context "/health" do
    it "includes running SHA, current time and status" do
      response = get '/health'
      expect(response.status).to eq(200)
      expect(response.headers["Content-Type"]).to eq("application/json")
      expect(JSON.parse(response.body)).to eq({
        "sha" => GIT_REVISION,
        "time" => Time.now.iso8601,
        "status" => "OK"
      })
    end
  end
end

require 'spec_helper'

describe Api::Health do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  context "/health" do
    it "includes running SHA, current time and status" do
      response = get '/health'
      response.status.should == 200
      response.headers["Content-Type"].should == "application/json"
      JSON.parse(response.body).should == {
        "sha" => GIT_REVISION,
        "time" => Time.now.iso8601,
        "status" => "DATABASE_UNREACHABLE" # it is in this test, but not under normal circumstances :)
      }
    end
  end
end

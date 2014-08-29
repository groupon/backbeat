require 'spec_helper'

describe Api::Health do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  context "/health" do
    it "includes running SHA, current time and status. if this fails locally, run a mongo on port 27018" do
      response = get '/health'
      ap  Mongoid.default_session.cluster.nodes.map(&:connected?)
      response.status.should == 200
      response.headers["Content-Type"].should == "application/json"
      JSON.parse(response.body).should == {
        "sha" => GIT_REVISION,
        "time" => Time.now.iso8601,
        "status" => "OK"
      }
    end
  end
end

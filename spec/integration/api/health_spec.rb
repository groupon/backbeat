require 'spec_helper'

describe Api::Health do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  context "/health" do
    it "catches the request and return 200" do
      response = get '/health'
      response.status.should == 200
      response.headers["Content-Type"].should == "text/plain"
      response.headers["Content-Length"].should == "0"
      response.body.should == ""
    end

    it "includes the date the last workflow was created" do
      wf = FactoryGirl.create(:workflow)
      response = get '/health'
      response.status.should == 200
      response.headers["Content-Type"].should == "text/plain"
      response.body.should == wf.created_at.to_s
    end
  end
end
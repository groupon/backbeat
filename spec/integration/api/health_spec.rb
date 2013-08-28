require 'spec_helper'

describe Api::Health do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  deploy BACKBEAT_APP


  context "/health" do
    it "catches the request and return 200" do
      get '/health'
      last_response.status.should == 200
      last_response.headers["Content-Type"].should == "text/plain"
      last_response.headers["Content-Length"].should == "0"
      last_response.body.should == ""
    end

    it "includes the date the last workflow was created" do
      wf = FactoryGirl.create(:workflow)
      get '/health'
      last_response.status.should == 200
      last_response.headers["Content-Type"].should == "text/plain"
      last_response.headers["Content-Length"].should == "25"
      last_response.body.should == wf.created_at.to_s
    end
  end
end
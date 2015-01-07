require 'spec_helper'

describe Api::Middleware::Heartbeat do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  context "/heartbeat.txt" do
    it "returns 200 if heartbeat present" do
      response = get '/heartbeat.txt'
      response.status.should == 200
      response.headers["Content-Type"].should == "text/plain"
      response.body.should == "We have a pulse."
    end

    it "returns 404 if heartbeat missing" do
      File.delete("#{File.dirname(__FILE__)}/../../../public/heartbeat.txt")
      response = get '/heartbeat.txt'
      response.status.should == 404
      response.headers["Content-Type"].should == "text/plain"
      response.body.should == "It's dead, Jim."
      File.open("#{File.dirname(__FILE__)}/../../../public/heartbeat.txt", "w") {|f|}
    end
  end
end

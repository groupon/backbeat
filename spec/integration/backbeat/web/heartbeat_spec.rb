require 'spec_helper'

describe Backbeat::Web::Middleware::Heartbeat, :api_test do

  context "/heartbeat.txt" do
    it "returns 200 if heartbeat present" do
      response = get '/heartbeat.txt'
      expect(response.status).to eq(200)
      expect(response.headers["Content-Type"]).to eq("text/plain")
      expect(response.body).to eq("We have a pulse.")
    end

    it "returns 503 if heartbeat missing" do
      File.delete("#{File.dirname(__FILE__)}/../../../../public/heartbeat.txt")
      response = get '/heartbeat.txt'
      expect(response.status).to eq(503)
      expect(response.headers["Content-Type"]).to eq("text/plain")
      expect(response.body).to eq("It's dead, Jim.")
      File.open("#{File.dirname(__FILE__)}/../../../../public/heartbeat.txt", "w") {|f|}
    end
  end
end

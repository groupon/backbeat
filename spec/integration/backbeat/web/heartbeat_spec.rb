require 'spec_helper'

describe Backbeat::Web::Middleware::Heartbeat, :api_test do

  def with_no_heartbeat
    heartbeat = "#{File.dirname(__FILE__)}/../../../../public/heartbeat.txt"
    begin
      File.delete(heartbeat)
      yield
    ensure
      File.open(heartbeat, 'w')
    end
  end

  context "/heartbeat.txt" do
    it "returns 200 if heartbeat present" do
      response = get '/heartbeat.txt'
      expect(response.status).to eq(200)
      expect(response.headers["Content-Type"]).to eq("text/plain")
      expect(response.body).to eq("We have a pulse.")
    end

    it "returns 503 if heartbeat missing" do
      with_no_heartbeat do
        response = get '/heartbeat.txt'
        expect(response.status).to eq(503)
        expect(response.headers["Content-Type"]).to eq("text/plain")
        expect(response.body).to eq("It's dead, Jim.")
      end
    end
  end
end

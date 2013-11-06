require 'spec_helper'

describe Api::SidekiqLatency do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  context '/sidekiq_latency' do
    it 'catches the request, returns 200 and the queue latency' do
      Sidekiq::Queue.stub_chain(:new, :latency).and_return(666)
      response = get '/sidekiq_latency'
      response.status.should == 200
      JSON.parse(response.body) == {"sidekiq_latency" => 666}
    end
  end
end

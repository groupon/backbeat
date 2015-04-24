require 'spec_helper'

describe Api::Middleware::Log do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  let(:wf) { FactoryGirl.create(:workflow) }

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
    WorkflowServer::Client.stub(:make_decision)
  end

  it "includes the transaction id in the response" do
    response = get "/workflows/#{wf.id}"
    response.status.should == 200
    response.headers.keys.should include("X-backbeat-tid")
  end

  it "logs route details" do
    log_count = 0
    expect_any_instance_of(Api::Middleware::Log).to receive(:info).twice do |response_info|
      log_count+=1
      if log_count == 2
        expect(response_info.to_json).to eq({
          :response=> {
            :status=>200,
            :type=>"workflows",
            :method=> wf.id,
            :env=>"/workflows/#{wf.id}",
            :duration=>0.0,
            :route_info=> {
              :version=>nil,
              :namespace=>"/workflows",
              :method=>"GET",
              :path=>"/workflows/:id(.:format)"
            }
          }
        }.to_json)
      end
    end
    response = get "/workflows/#{wf.id}"
    response.status.should == 200
  end
end

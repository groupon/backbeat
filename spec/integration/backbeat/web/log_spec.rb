require 'spec_helper'

describe Backbeat::Web::Middleware::Log do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:wf) { FactoryGirl.create(:workflow, user: user) }

  before do
    header 'CLIENT_ID', user.id
    Backbeat::Client.stub(:make_decision)
  end

  it "includes the transaction id in the response" do
    response = get "v2/workflows/#{wf.id}"
    response.status.should == 200
    response.headers.keys.should include("X-backbeat-tid")
  end

  it "logs route details" do
    log_count = 0
    expect_any_instance_of(described_class).to receive(:info).twice do |response_info|
      log_count+=1
      if log_count == 2
        expect(response_info.to_json).to eq({
          :response=> {
            :status=>200,
            :type=>"workflows",
            :method=> wf.id,
            :env=>"/v2/workflows/#{wf.id}",
            :duration=>0.0,
            :route_info=> {
              :version=>'v2',
              :namespace=>"/workflows",
              :method=>"GET",
              :path=>"/:version/workflows/:id(.:format)"
            }
          }
        }.to_json)
      end
    end
    response = get "v2/workflows/#{wf.id}"
    response.status.should == 200
  end
end

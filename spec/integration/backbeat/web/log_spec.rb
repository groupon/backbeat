require 'spec_helper'

describe Backbeat::Web::Middleware::Log, :api_test do
  let(:user) { FactoryGirl.create(:user) }
  let(:wf) { FactoryGirl.create(:workflow, user: user) }

  before do
    allow(Backbeat::Client).to receive(:make_decision)
  end

  it "includes the transaction id in the response" do
    response = get "v2/workflows/#{wf.id}"
    expect(response.status).to eq(200)
    expect(response.headers.keys).to include("X-backbeat-tid")
  end

  it "logs route details" do
    log_count = 0
    expect(Backbeat::Logger).to receive(:info).twice do |response_info|
      log_count += 1
      if log_count == 2
        expect(response_info).to eq({
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
              :path=>"/:version/workflows/:id"
            }
          }
        })
      end
    end
    response = get "v2/workflows/#{wf.id}"
    expect(response.status).to eq(200)
  end
end

require "grape"
require 'spec_helper'
require "spec/helper/request_helper"

describe Api::Middleware::Log, v2: true do
  include Rack::Test::Methods
  include RequestHelper

  def app
    FullRackApp
  end

  let(:v2_user) { FactoryGirl.create(:v2_user) }
  let(:v2_workflow) { FactoryGirl.create(:v2_workflow, user: v2_user) }

  before do
    header 'CLIENT_ID', v2_user.id
  end

  it "logs route details" do
    log_count = 0
    expect_any_instance_of(Api::Middleware::Log).to receive(:info).twice do |response_info|
      log_count+=1
      if log_count == 2
        expect(response_info.to_json).to eq({
          :response=> {
            :status=>201,
            :type=>"v2",
            :method=>"test",
            :env=>"/v2/workflows/#{v2_workflow.id}/signal/test",
            :duration=>0.0,
            :route_info=>{
              :version=>"v2",
              :namespace=>"/workflows",
              :method=>"POST",
              :path=>"/:version/workflows/:id/signal/:name(.:format)"
            }
          }
        }.to_json)
      end
    end
    post "v2/workflows/#{v2_workflow.id}/signal/test", options: {
      client_data: { data: '123' },
      client_metadata: { metadata: '456'}
    }
  end
end

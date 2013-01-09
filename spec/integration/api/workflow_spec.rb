require 'spec_helper'

describe Api::Workflow do
  # Methods to help with testing Goliath APIs
  #
  # @example
  #   describe Echo do
  #     include Goliath::TestHelper
  #
  #     let(:err) { Proc.new { fail "API request failed" } }
  #     it 'returns the echo param' do
  #       with_api(Echo) do
  #         get_request({:query => {:echo => 'test'}}, err) do |c|
  #           b = MultiJson.load(c.response)
  #           b['response'].should == 'test'
  #         end
  #       end
  #     end
  #   end
  #
  include Goliath::TestHelper
  it "returns 401 without the client it header" do
    with_api(Server) do |api|
      post_request(path: '/workflows') do |c|
        c.response_header.status.should == 401
        c.response.should == "Unauthorized"
      end
    end
  end

  it "returns 400 when one of the required params is missing" do
    with_api(Server) do |api|
      user = FactoryGirl.create(:user)
      post_request(path: '/workflows', head: {"CLIENT_ID" => user.client_id}) do |c|
        c.response_header.status.should == 400
        json_response = JSON.parse(c.response)
        json_response['error'].should == "missing parameter: workflow_type"
      end
    end
  end

  it "returns 201 and creates a new workflow when all parameters present" do
    with_api(Server) do |api|
      user = FactoryGirl.create(:user)
      post_request(path: '/workflows', head: {"CLIENT_ID" => user.client_id}, query: {workflow_type: "WFType", subject_type: "PaymentTerm", subject_id: 100, decider: "PaymentDecider"}) do |c|
        c.response_header.status.should == 201
        json_response = JSON.parse(c.response)
        wf = json_response.last
        wf_in_db = WorkflowServer::Models::Workflow.last
        wf_in_db.id.to_s.should == wf['_id']
      end
    end
  end

  it "returns workflow from database if it already exists" do
    with_api(Server) do |api|
      wf = FactoryGirl.create(:workflow)
      user = wf.user
      post_request(path: '/workflows', head: {"CLIENT_ID" => user.client_id}, query: {workflow_type: wf.workflow_type, subject_type: wf.subject_type, subject_id: wf.subject_id, decider: wf.decider}) do |c|
        c.response_header.status.should == 201
        json_response = JSON.parse(c.response)
        new_wf = json_response.last
        wf.id.to_s.should == new_wf['_id']
      end
    end
  end
end
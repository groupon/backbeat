require 'spec_helper'

describe Api::Workflows, v2: true do
  include Rack::Test::Methods

  deploy BACKBEAT_APP

  def app
    FullRackApp
  end

  let(:v2_user) { FactoryGirl.create(:v2_user) }

  before do
    header 'CLIENT_ID', v2_user.id
    WorkflowServer::Client.stub(:make_decision)
  end

  context "POST /workflows" do
    it "returns 201 and creates a new workflow when all parameters present" do
      response = post '/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}
      json_response = JSON.parse(response.body)
      wf_in_db = V2::Workflow.find(json_response['id'])
      wf_in_db.should_not be_nil
      wf_in_db.subject.should == {"subject_klass" => "PaymentTerm", "subject_id" => "100"}

      response = post '/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}
      json_response['id'].should ==  JSON.parse(response.body)['id']
    end
  end
end

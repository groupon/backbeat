require 'spec_helper'

describe WorkflowServer do
  let (:user) { FactoryGirl.create(:user) }
  let (:options) { {subject: {sub: 1}, workflow_type: :test, name: :test, decider: :test, user: user} }
  let (:error) { Moped::Errors::OperationFailure.new("Moped::Protocol::Command", {"err"=>"E11000 duplicate key error, workflow_uat.workflow_server_models_events.$workflow_type_1_subject_1  dup key: { : \"citydeal_workflow\", : { subject_klass: \"CityDealDeal\", subject_id: 26567 } }", "code"=>11000, "n"=>0 }) }
  context '#find_or_create_by' do

    it "retries on duplicate key error" do
      WorkflowServer::Models::Workflow.should_receive(:find_or_create_by).with(options).twice.and_raise(error)
      expect {
        WorkflowServer.find_or_create_workflow(options)
      }.to raise_error(Moped::Errors::OperationFailure)
    end
  end
end

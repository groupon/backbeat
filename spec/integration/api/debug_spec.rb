require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  def create_stuck_workflow(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    decision = FactoryGirl.create(:decision, workflow: workflow, status: :open)
    decision.update_status!(:open)
    workflow
  end

  def create_multiple_decision_workflow(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    FactoryGirl.create(:decision, workflow: workflow, status: :executing)
    FactoryGirl.create(:decision, workflow: workflow, status: :enqueued)
    workflow
  end

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  context '/debug/stuck_workflows' do
    it 'returns empty when none stuck' do
      user
      get "/debug/stuck_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.should be_empty
    end
    it 'returns an array of the stuck workflows for the user' do
      wf1 = create_stuck_workflow(user, workflow)
      wf2 = create_stuck_workflow(user)
      wf3 = create_stuck_workflow(user)
      wf3.decisions.first.update_status!(:enqueued)
      wf4 = create_stuck_workflow(FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s))

      get "/debug/stuck_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 2
      ids = json_response.map { |r| r['id'] }
      ids.should include(wf1.id)
      ids.should include(wf2.id)
    end
  end

  context '/debug/multiple_executing_decisions' do
    it "returns empty when nothing of interest" do
      workflow
      get "/debug/multiple_executing_decisions"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.should be_empty
    end
    it "returns workflows when more than one decision executing at the same time" do
      wf1 = create_multiple_decision_workflow(user, workflow)
      wf2 = create_multiple_decision_workflow(user)
      wf3 = create_multiple_decision_workflow(user)
      wf3.decisions.first.update_status!(:open)
      wf4 = create_multiple_decision_workflow(FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s))
      get "/debug/multiple_executing_decisions"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 2
      ids = json_response.map { |r| r['id'] }
      ids.should include(wf1.id)
      ids.should include(wf2.id)
    end
  end
end
require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  def create_error_workflow(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    decision = FactoryGirl.create(:decision, workflow: workflow, status: :error)
    workflow
  end

  def create_paused_workflow(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    workflow.pause
    decision = FactoryGirl.create(:decision, workflow: workflow, status: :open)
    workflow
  end

  def create_stuck_workflow(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    decision = FactoryGirl.create(:decision, workflow: workflow, status: :open)
    decision.update_status!(:open)
    workflow
  end

  def create_long_running_event(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    decision = FactoryGirl.create(:decision, workflow: workflow, status: :executing, updated_at: 2.days.ago)
    workflow
  end

  def create_multiple_decision_workflow(for_user, workflow = nil)
    workflow ||= FactoryGirl.create(:workflow, user: for_user)
    FactoryGirl.create(:decision, workflow: workflow, status: :executing)
    FactoryGirl.create(:decision, workflow: workflow, status: :enqueued)
    workflow
  end

  def create_duplicate_decisions_on_event(p_workflow, event = :timer)
    event = FactoryGirl.create(event, workflow: p_workflow)
    2.times { event.children << FactoryGirl.create(:decision, workflow: p_workflow, parent: event) }
    event
  end

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  context '/debug/error_workflows' do
    it 'returns empty when no error workflows' do
      user
      get "/debug/error_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.should be_empty
    end
    it "returns workflows with activities / decisions in error state" do
      wf1 = create_error_workflow(user, workflow)
      wf2 = create_error_workflow(user)
      wf3 = create_error_workflow(user)
      wf3.decisions.first.update_status!(:enqueued)
      wf4 = create_error_workflow(FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s))

      get "/debug/error_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 2
      ids = json_response.map { |r| r['id'] }
      ids.should include(wf1.id)
      ids.should include(wf2.id)
    end
    it "filters error workflows with activities / decisions in error state" do
      wf1 = create_error_workflow(user, workflow)
      wf2 = create_error_workflow(user)
      wf3 = create_error_workflow(user)
      wf2.pause

      get "/debug/error_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 2
      ids = json_response.map { |r| r['id'] }
      ids.should include(wf1.id)
      ids.should_not include(wf2.id)
      ids.should include(wf3.id)
    end
  end

  context '/debug/paused_workflows' do
    it 'returns empty when no paused workflows' do
      user
      get "/debug/paused_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.should be_empty
    end
    it "returns workflows that are in a paused state" do
      wf1 = create_paused_workflow(user, workflow)
      wf2 = create_paused_workflow(user)
      wf3 = create_paused_workflow(user)

      get "/debug/paused_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 3
      ids = json_response.map { |r| r['id'] }
      ids.should include(wf1.id)
      ids.should include(wf2.id)
      ids.should include(wf3.id)
    end
  end

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
      wf5 = create_paused_workflow(user)

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

  context '/debug/long_running_events' do
    it 'returns empty when none stuck' do
      user
      get "/debug/long_running_events"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.should be_empty
    end
    it 'returns an array of workflows with long running events for the user' do
      wf1 = create_long_running_event(user, workflow)
      wf2 = create_long_running_event(user)
      wf3 = create_long_running_event(FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s))

      get "/debug/long_running_events"
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

  context '/debug/inconsistent_workflows' do
    it "returns empty when nothing of interest" do
      workflow
      get "/debug/inconsistent_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.should be_empty
    end
    it 'returns workflows that have timers with multiple decisions' do
      t1 = create_duplicate_decisions_on_event(workflow)
      t2 = create_duplicate_decisions_on_event(FactoryGirl.create(:workflow, user: user))
      t3 = create_duplicate_decisions_on_event(workflow)
      t3.children.first.destroy
      t4 = create_duplicate_decisions_on_event(FactoryGirl.create(:workflow, user: FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s)))
      get "/debug/inconsistent_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 2
      ids = json_response.map { |r| r['id'] }
      ids.should include(t1.workflow.id)
      ids.should include(t2.workflow.id)
    end
    it "returns workflows that have signals with multiple decisions" do
      s1 = create_duplicate_decisions_on_event(workflow, :signal)
      s2 = create_duplicate_decisions_on_event(FactoryGirl.create(:workflow, user: user), :signal)
      s3 = create_duplicate_decisions_on_event(workflow, :signal)
      s3.children.first.destroy
      s4 = create_duplicate_decisions_on_event(FactoryGirl.create(:workflow, user: FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s)), :signal)
      get "/debug/inconsistent_workflows"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_instance_of(Array)
      json_response.count.should == 2
      ids = json_response.map { |r| r['id'] }
      ids.should include(s1.workflow.id)
      ids.should include(s2.workflow.id)
    end
  end
end

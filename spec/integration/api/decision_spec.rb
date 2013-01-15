require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
    WorkflowServer::AsyncClient.stub(:make_decision)
  end

  context "PUT /workflows/:id/events/:event_id/change_status" do
    context "change state to deciding" do
      it "raises 400 if decision was never enqueued" do
        decision = FactoryGirl.create(:decision, status: :open)
        decision.reload.update_status!(:open)
        wf = decision.workflow
        user = wf.user
        put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :deciding}
        last_response.status.should == 400
        decision.reload
        decision.status.should == :open
        json_response = JSON.parse(last_response.body)
        json_response['error'].should == "Decision #{decision.name} can't transition from open to deciding"
      end

      it "puts a decision in deciding state if enqueued" do
        decision = FactoryGirl.create(:decision, status: :enqueued)
        wf = decision.workflow
        user = wf.user
        put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :deciding}
        last_response.status.should == 200
        decision.reload
        decision.status.should == :deciding
      end
    end
  end

  context "change status to deciding_complete" do
    it "raises 400 if decision is not in deciding/enqueued state" do
      decision = FactoryGirl.create(:decision, status: :open)
      decision.reload.update_status!(:open)
      wf = decision.workflow
      user = wf.user
      put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :deciding_complete}
      last_response.status.should == 400
      decision.reload
      decision.status.should == :open
      json_response = JSON.parse(last_response.body)
      json_response['error'].should == "Decision #{decision.name} can't transition from open to deciding_complete"
    end

    it "returns 400 if some of the decisions are incorrectly formed" do
      decision = FactoryGirl.create(:decision, status: :enqueued)
      wf = decision.workflow
      user = wf.user
      decisions = [
        {type: :flag, name: :wFlag},
        {type: :timer, name: :wTimer, fires_at: Time.now + 1000.seconds},
        {type: :activity, name: :make_initial_payment, actor_id: 100, retry: 100, retry_interval: 5},
        {type: :branch, name: :make_initial_payment_branch, actor_id: 100, retry: 100, retry_interval: 5},
        {type: :workflow, name: :some_name, subject_type: "PaymentTerm", subject_id: 1000, decider: "ErrorDecider"},
        {type: :complete_workflow}
      ]
      put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :deciding_complete, args: {decisions: decisions}.to_json}
      last_response.status.should == 400
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error"=>[{"some_name"=>{"workflow_type"=>["can't be blank"]}}]}
      decision.reload
      decision.children.count.should == 0
      decision.status.should_not == :executing
    end

    it "puts a decision in deciding_complete state and registers the decision" do
      decision = FactoryGirl.create(:decision, status: :enqueued)
      wf = decision.workflow
      user = wf.user
      args = [
        {type: :flag, name: :wFlag},
        {type: :timer, name: :wTimer, fires_at: Time.now + 1000.seconds},
        {type: :activity, name: :make_initial_payment, actor_type: "LineItem", actor_id: 100, retry: 100, retry_interval: 5},
        {type: :branch, name: :make_initial_payment_branch, actor_id: 100, retry: 100, retry_interval: 5},
        {type: :workflow, name: :some_name, workflow_type: :error_recovery_workflow, subject_type: "PaymentTerm", subject_id: 1000, decider: "ErrorDecider"},
        {type: :complete_workflow}
      ]
      put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :deciding_complete, args: args.to_json}
      last_response.status.should == 200
      decision.reload
      decision.children.count.should == 6
      # TODO Compare the children
      decision.status.should == :executing
    end

    context "decision errored" do
      it "returns 400 if the decision is not in enqueued/deciding state" do
        decision = FactoryGirl.create(:decision, status: :open)
        decision.reload.update_status!(:open)
        wf = decision.workflow
        user = wf.user
        put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :errored}
        last_response.status.should == 400
        json_response = JSON.parse(last_response.body)
        json_response['error'].should == "Decision #{decision.name} can't transition from open to errored"
      end
      it "returns 200 and records the error message" do
        decision = FactoryGirl.create(:decision, status: :open)
        wf = decision.workflow
        user = wf.user
        put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :errored, args: {error: {a: 1, b: 2}}.to_json}
        last_response.status.should == 200
        decision.reload
        decision.status.should == :error
        decision.status_history.last["error"].should == {"a"=>1, "b"=>2}
      end
    end
  end
  context "invalid status" do
    it "raises 400 if invalid new status" do
      decision = FactoryGirl.create(:decision)
      wf = decision.workflow
      user = wf.user
      put "/workflows/#{wf.id}/events/#{decision.id}/change_status", {status: :something_invalid}
      last_response.status.should == 400
      decision.reload
      json_response = JSON.parse(last_response.body)
      json_response['error'].should == "Invalid status something_invalid"
    end
  end
end
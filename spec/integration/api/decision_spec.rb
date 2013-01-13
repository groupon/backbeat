require 'spec_helper'

describe Api::Workflow do
  include Goliath::TestHelper

  before do
    WorkflowServer::AsyncClient.stub(:make_decision)
  end

  context "PUT /workflows/:id/events/:event_id/change_status" do
    context "change state to deciding" do
      it "raises 400 if decision was never enqueued" do
        with_api(Server) do |api|
          decision = FactoryGirl.create(:decision, status: :open)
          decision.reload.update_status!(:open)
          wf = decision.workflow
          user = wf.user
          put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :deciding}) do |c|
            c.response_header.status.should == 400
            decision.reload
            decision.status.should == :open
            json_response = JSON.parse(c.response)
            json_response['error'].should == "Decision #{decision.name} can't transition from open to deciding"
          end
        end
      end

      it "puts a decision in deciding state if enqueued" do
        with_api(Server) do |api|
          decision = FactoryGirl.create(:decision, status: :enqueued)
          wf = decision.workflow
          user = wf.user
          put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :deciding}) do |c|
            c.response_header.status.should == 200
            decision.reload
            decision.status.should == :deciding
          end
        end
      end
    end

    context "change status to deciding_complete" do
      it "raises 400 if decision is not in deciding/enqueued state" do
        with_api(Server) do |api|
          decision = FactoryGirl.create(:decision, status: :open)
          decision.reload.update_status!(:open)
          wf = decision.workflow
          user = wf.user
          put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :deciding_complete}) do |c|
            c.response_header.status.should == 400
            decision.reload
            decision.status.should == :open
            json_response = JSON.parse(c.response)
            json_response['error'].should == "Decision #{decision.name} can't transition from open to deciding_complete"
          end
        end
      end

      it "returns 400 if some of the decisions are incorrectly formed" do
        with_api(Server) do |api|
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
          put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :deciding_complete, args: {decisions: decisions}.to_json}) do |c|
            c.response_header.status.should == 400
            json_response = JSON.parse(c.response)
            json_response.should == {"error"=>[{"some_name"=>{"workflow_type"=>["can't be blank"]}}]}
            decision.reload
            decision.children.count.should == 0
            decision.status.should_not == :executing
          end
        end
      end

      it "puts a decision in deciding_complete state and registers the decision" do
        with_api(Server) do |api|
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
          put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :deciding_complete, args: args.to_json}) do |c|
            c.response_header.status.should == 200
            decision.reload
            decision.children.count.should == 6
            # TODO Compare the children
            decision.status.should == :executing
          end
        end
      end
      context "decision errored" do
        it "returns 400 if the decision is not in enqueued/deciding state" do
          with_api(Server) do |api|
            decision = FactoryGirl.create(:decision, status: :open)
            decision.reload.update_status!(:open)
            wf = decision.workflow
            user = wf.user
            put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :errored}) do |c|
              c.response_header.status.should == 400
              json_response = JSON.parse(c.response)
              json_response['error'].should == "Decision #{decision.name} can't transition from open to errored"
            end
          end
        end
        it "returns 200 and records the error message" do
          with_api(Server) do |api|
            decision = FactoryGirl.create(:decision, status: :open)
            wf = decision.workflow
            user = wf.user
            put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :errored, args: {error: {a: 1, b: 2}}.to_json}) do |c|
              c.response_header.status.should == 200
              decision.reload
              decision.status.should == :error
              decision.status_history.last["error"].should == {"a"=>1, "b"=>2}
            end
          end
        end
      end
    end
    context "invalid status" do
      it "raises 400 if invalid new status" do
        with_api(Server) do |api|
          decision = FactoryGirl.create(:decision)
          wf = decision.workflow
          user = wf.user
          put_request(path: "/workflows/#{wf.id}/events/#{decision.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :something_invalid}) do |c|
            c.response_header.status.should == 400
            decision.reload
            json_response = JSON.parse(c.response)
            json_response['error'].should == "Invalid status something_invalid"
          end
        end
      end
    end
  end
end
require 'spec_helper'

describe Api::Workflow do
  include Goliath::TestHelper

  context "PUT /workflows/:id/events/:event_id/change_status" do
    context "invalid status" do
      it "raises 400 if invalid new status" do
        with_api(Server) do |api|
          activity = FactoryGirl.create(:activity)
          wf = activity.workflow
          user = wf.user
          put_request(path: "/workflows/#{wf.id}/events/#{activity.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :something_invalid}) do |c|
            c.response_header.status.should == 400
            activity.reload
            json_response = JSON.parse(c.response)
            json_response['error'].should == "Invalid status something_invalid"
          end
        end
      end
      context "activity completed" do
        it "returns 400 if the activity is not in executing state" do
          with_api(Server) do |api|
            activity = FactoryGirl.create(:activity, status: :open)
            wf = activity.workflow
            user = wf.user
            put_request(path: "/workflows/#{wf.id}/events/#{activity.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :completed}) do |c|
              c.response_header.status.should == 400
              activity.reload
              json_response = JSON.parse(c.response)
              json_response['error'].should == "Activity #{activity.name} can't transition from open to completed"
            end
          end
        end
        it "marks the activity as completed when in executing status" do
          with_api(Server) do |api|
            activity = FactoryGirl.create(:activity, status: :executing)
            wf = activity.workflow
            user = wf.user
            put_request(path: "/workflows/#{wf.id}/events/#{activity.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :completed}) do |c|
              c.response_header.status.should == 200
              activity.reload
              activity.status.should == :complete
            end
          end
        end
      end
      context "activity errored" do
        it "returns 400 if the activity is not in executing state" do
          with_api(Server) do |api|
            activity = FactoryGirl.create(:activity, status: :open)
            wf = activity.workflow
            user = wf.user
            put_request(path: "/workflows/#{wf.id}/events/#{activity.id}/change_status", head: {"CLIENT_ID" => user.client_id}, query: {status: :errored}) do |c|
              c.response_header.status.should == 400
              activity.reload
              json_response = JSON.parse(c.response)
              json_response['error'].should == "Activity #{activity.name} can't transition from open to errored"
            end
          end
        end
      end
    end
  end
end
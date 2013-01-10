require 'spec_helper'

describe Api::Workflow do
  include Goliath::TestHelper
  
  context "GET /events/id" do
    it "returns an event object with valid params" do
      with_api(Server) do |api|
        decision = FactoryGirl.create(:decision)
        get_request(path: "/events/#{decision.id}", head: {"CLIENT_ID" => decision.workflow.user.client_id}) do |c|
          c.response_header.status.should == 200
          json_response = JSON.parse(c.response)
          json_response['_id'].should == decision.id.to_s
        end
      end
    end

    it "returns a 404 if the event is not found" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        get_request(path: "/events/1000", head: {"CLIENT_ID" => wf.user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Event with id(1000) not found"}
        end
      end
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      with_api(Server) do |api|
        decision = FactoryGirl.create(:decision)
        user = FactoryGirl.create(:user)
        get_request(path: "/events/#{decision.id}", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Event with id(#{decision.id}) not found"}
        end
      end
    end
  end
end
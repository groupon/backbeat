require 'spec_helper'

describe Api::Workflow do
  include Goliath::TestHelper

  context "POST /workflows" do
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
          json_response.should == {"error" => {"name"=>["can't be blank"], "workflow_type"=>["can't be blank"], "subject_id"=>["can't be blank"], "subject_type"=>["can't be blank"], "decider"=>["can't be blank"]}}
        end
      end
    end

    it "returns 201 and creates a new workflow when all parameters present" do
      with_api(Server) do |api|
        user = FactoryGirl.create(:user)
        post_request(path: '/workflows', head: {"CLIENT_ID" => user.client_id}, query: {workflow_type: "WFType", subject_type: "PaymentTerm", subject_id: 100, decider: "PaymentDecider"}) do |c|
          c.response_header.status.should == 201
          json_response = JSON.parse(c.response)
          wf = json_response
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
          new_wf = json_response
          wf.id.to_s.should == new_wf['_id']
        end
      end
    end
  end

  context "POST /workflows/id/signal/name" do
    it "returns 404 when workflow not found" do
      with_api(Server) do |api|
        user = FactoryGirl.create(:user)
        post_request(path: "/workflows/1000/signal/test", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(1000) not found"}
        end
      end
    end

    it "returns 201 and the signal json if workflow exists" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        user = wf.user
        # TODO - Put a webmock here once we actually call out to the accounting service
        WorkflowServer::AsyncClient.should_receive(:make_decision)
        post_request(path: "/workflows/#{wf.id}/signal/test", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 201
          json_response = JSON.parse(c.response)
          signal = json_response
          wf.signals.first.id.to_s.should == signal['_id']
        end
      end
    end

    it "returns 400 if the workflow is closed for events" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow, status: :complete)
        user = wf.user
        post_request(path: "/workflows/#{wf.id}/signal/test", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 400
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(#{wf.id}) is already complete"}
        end
      end
    end
    
    it "returns a 404 if a user tries to send a signal to a workflow that doesn't belong to them" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        user = FactoryGirl.create(:user)
        post_request(path: "/workflows/#{wf.id}/signal/test", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(#{wf.id}) not found"}
        end
      end
    end
  end

  context "GET /workflows/id" do
    it "returns a workflow object with valid params" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        get_request(path: "/workflows/#{wf.id}", head: {"CLIENT_ID" => wf.user.client_id}) do |c|
          c.response_header.status.should == 200
          json_response = JSON.parse(c.response)
          json_response['_id'].should == wf.id.to_s
        end
      end
    end

    it "returns a 404 if the workflow is not found" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        get_request(path: "/workflows/1000", head: {"CLIENT_ID" => wf.user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(1000) not found"}
        end
      end
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        user = FactoryGirl.create(:user)
        get_request(path: "/workflows/#{wf.id}", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(#{wf.id}) not found"}
        end
      end
    end
  end

  context "GET /workflows/id/events" do
    it "returns a workflow object with valid params" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        d1 = FactoryGirl.create(:decision, workflow: wf)
        d2 = FactoryGirl.create(:decision, workflow: wf)
        get_request(path: "/workflows/#{wf.id}/events", head: {"CLIENT_ID" => wf.user.client_id}) do |c|
          c.response_header.status.should == 200
          json_response = JSON.parse(c.response)
          json_response.count.should == 2
          json_response.map {|obj| obj["_id"] }.should == [d1, d2].map(&:id).map(&:to_s)
        end
      end
    end

    it "returns a 404 if the workflow is not found" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        get_request(path: "/workflows/1000/events", head: {"CLIENT_ID" => wf.user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(1000) not found"}
        end
      end
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      with_api(Server) do |api|
        wf = FactoryGirl.create(:workflow)
        user = FactoryGirl.create(:user)
        get_request(path: "/workflows/#{wf.id}/events", head: {"CLIENT_ID" => user.client_id}) do |c|
          c.response_header.status.should == 404
          json_response = JSON.parse(c.response)
          json_response.should == {"error" => "Workflow with id(#{wf.id}) not found"}
        end
      end
    end
  end
end
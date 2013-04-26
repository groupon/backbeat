require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
    WorkflowServer::Client.stub(:make_decision)
    @user = FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s)
    @d1 = FactoryGirl.create(:decision, workflow: workflow)
  end

  def uri(template, event)
    event_id = event.id
    workflow_id = event.workflow.id
    message = ERB.new(template)
    message.result(binding)
  end

  ["/workflows/<%=workflow_id%>/events/<%=event_id%>", "/events/<%=event_id%>"].each do |template|
    context "GET #{template}" do
      it "returns an event object with valid params" do
        get uri(template, @d1)
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response.should == {"clientData"=>{}, "createdAt"=>Time.now.to_datetime.to_s, "decider" => "PaymentDecider", "name"=>"WFDecision", "parentId"=>nil, "status"=>"open", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@d1.workflow.id, "id"=>@d1.id, "type"=>"decision", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}}
        json_response['id'].should == @d1.id.to_s
      end

      it "returns the past flags" do
        name = 'decision'
        flag = FactoryGirl.create(:flag, name: "#{name}_completed", workflow: workflow)
        decision = FactoryGirl.create(:decision, name: name, workflow: workflow)
        get uri(template, decision)
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
      end

      it "returns a 404 if the event is not found" do
        event = mock('mock', id: 1000, workflow: workflow)
        get uri(template, event)
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == {"error" => "Event with id(1000) not found"}
      end

      it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
        decision = FactoryGirl.create(:decision, workflow: workflow)
        user = FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s)
        header 'CLIENT_ID', user.id
        get uri(template, decision)
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == (template.match(/^\/workflows/) ? {"error" => "Workflow with id(#{decision.workflow.id}) not found"} : {"error" => "Event with id(#{decision.id}) not found"})
      end
    end

    context "GET #{template}/history_decisions" do
      it "empty array when no history" do
        get "#{uri(template, @d1)}/history_decisions"
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response["historyDecisions"].should == []
      end
      it "returns all the decisions before the given event" do
        decision1 = FactoryGirl.create(:decision, workflow: workflow, status: :complete)
        decision2 = FactoryGirl.create(:decision, workflow: workflow, status: :executing)
        decision3 = FactoryGirl.create(:decision, workflow: workflow, status: :executing)
        decision4 = FactoryGirl.create(:decision, workflow: workflow, status: :complete)
        get "#{uri(template, decision3)}/history_decisions"
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response["historyDecisions"].size.should == 3
        json_response["historyDecisions"].first['id'].should == @d1.id
        json_response["historyDecisions"][1]['id'].should == decision1.id
        json_response["historyDecisions"].last['id'].should == decision2.id
      end

      it "returns a 404 if the event is not found" do
        event = mock('mock', id: 1000, workflow: @d1.workflow)
        get "#{uri(template, event)}/history_decisions"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == {"error" => "Event with id(1000) not found"}
      end

      it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
        header 'CLIENT_ID', @user.id
        get "#{uri(template, @d1)}/history_decisions"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == (template.match(/^\/workflows/) ? {"error" => "Workflow with id(#{@d1.workflow.id}) not found"} : {"error" => "Event with id(#{@d1.id}) not found"})
      end
    end

    context "GET #{template}/tree" do
      it "returns a tree of the event with valid params" do
        get "#{uri(template, @d1)}/tree"
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response.should == {"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"open"}
      end

      it "returns a 404 if the event is not found" do
        event = mock('mock', id: 1000, workflow: @d1.workflow)
        get "#{uri(template, event)}/tree"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == {"error" => "Event with id(1000) not found"}
      end

      it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
        header 'CLIENT_ID', @user.id
        get "#{uri(template, @d1)}/tree"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == (template.match(/^\/workflows/) ? {"error" => "Workflow with id(#{@d1.workflow.id}) not found"} : {"error" => "Event with id(#{@d1.id}) not found"})
      end
    end

    context "GET #{template}/print" do
      it "returns a tree of the event with valid params" do
        get "#{uri(template, @d1)}/tree/print"
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response["print"].should be_a(String)
      end

      it "returns a 404 if the event is not found" do
        event = mock('mock', id: 1000, workflow: @d1.workflow)
        get "#{uri(template, event)}/tree/print"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == {"error" => "Event with id(1000) not found"}
      end

      it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
        header 'CLIENT_ID', @user.id
        get "#{uri(template, @d1)}/tree/print"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == (template.match(/^\/workflows/) ? {"error" => "Workflow with id(#{@d1.workflow.id}) not found"} : {"error" => "Event with id(#{@d1.id}) not found"})
      end
    end
  end

  # specific to the workflow endpoint
  ["/workflows/<%=workflow_id%>/events/<%=event_id%>"].each do |template|
    context "GET #{template}/tree" do
      it "returns a 404 if the workflow is not found" do
        @d1.stub_chain(:workflow, :id => 1000)
        get "#{uri(template, @d1)}/tree"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == {"error" => "Workflow with id(1000) not found"}
      end
    end
    context "GET #{template}/print" do
      it "returns a 404 if the workflow is not found" do
        @d1.stub_chain(:workflow, :id => 1000)
        get "#{uri(template, @d1)}/tree/print"
        last_response.status.should == 404
        json_response = JSON.parse(last_response.body)
        json_response.should == {"error" => "Workflow with id(1000) not found"}
      end
    end
  end
end

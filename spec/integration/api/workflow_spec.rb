require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  def app
    FullRackApp
  end

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
    WorkflowServer::Client.stub(:make_decision)

    @wf = FactoryGirl.create(:workflow)
    @d1 = FactoryGirl.create(:decision, workflow: @wf)
    @d2 = FactoryGirl.create(:decision, workflow: @wf)
    @user = FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s)
  end

  context "POST /workflows" do
    it "returns 401 without the client it header" do
      header 'CLIENT_ID', '12'
      post '/workflows'
      last_response.status.should == 401
      last_response.body.should == "Unauthorized"
    end

    it "returns 400 when one of the required params is missing" do
      post '/workflows'
      last_response.status.should == 400
      JSON.parse(last_response.body).should == {"error" => {"name"=>["can't be blank"], "workflowType"=>["can't be blank"], "subjectId"=>["can't be blank"], "subjectKlass"=>["can't be blank"], "decider"=>["can't be blank"]}}
    end

    it "returns 201 and creates a new workflow when all parameters present" do
      post '/workflows', {workflow_type: "WFType", subject_klass: "PaymentTerm", subject_id: 100, decider: "PaymentDecider"}
      last_response.status.should == 201
      json_response = JSON.parse(last_response.body)
      new_wf = json_response
      wf_in_db = WorkflowServer::Models::Workflow.last
      wf_in_db.id.to_s.should == new_wf['id']
    end

    it "returns workflow from database if it already exists" do
      post '/workflows', {workflow_type: @wf.workflow_type, subject_klass: @wf.subject_klass, subject_id: @wf.subject_id, decider: @wf.decider}
      last_response.status.should == 201
      json_response = JSON.parse(last_response.body)
      new_wf = json_response
      @wf.id.to_s.should == new_wf['id']
    end
  end

  context "POST /workflows/id/signal/name" do
    it "returns 404 when workflow not found" do
      post "/workflows/1000/signal/test"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns 201 and the signal json if workflow exists" do
      @wf = FactoryGirl.create(:workflow)
      @user = @wf.user
      Delayed::Job.destroy_all
      post "/workflows/#{@wf.id}/signal/test"
      last_response.status.should == 201
      signal = JSON.parse(last_response.body)
      @wf.signals.first.id.to_s.should == signal['id']
      Delayed::Job.where(handler: /send_to_client/).count.should == 1
      Delayed::Job.where(handler: /notify_client/).count.should == 3
    end

    it "returns 400 if the workflow is closed for events" do
      @wf.update_attributes(status: :complete)
      post "/workflows/#{@wf.id}/signal/test"
      last_response.status.should == 400
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) is already complete"}
    end

    it "returns a 404 if a user tries to send a signal to a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      post "/workflows/#{@wf.id}/signal/test"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/id" do
    it "returns a workflow object with valid params" do
      get "/workflows/#{@wf.id}"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"createdAt"=>Time.now.to_datetime.to_s, "decider"=>"PaymentDecider", "errorWorkflow"=>false, "mode"=>"blocking", "name"=>"WFType", "parentId"=>nil, "status"=>"open", "subjectId"=>@wf.subject_id, "subjectKlass"=>@wf.subject_klass, "updatedAt"=>Time.now.to_datetime.to_s, "userId"=>@wf.user.id, "workflowId"=>nil, "workflowType"=>"WFType", "id"=>@wf.id, "type"=>"workflow"}
      json_response['id'].should == @wf.id.to_s
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/id/events" do
    it "returns a workflow object with valid params" do
      get "/workflows/#{@wf.id}/events"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == [{"createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"enqueued", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "pastFlags"=>[], "decider"=>"PaymentDecider", "subjectKlass"=>"PaymentTerm", "subjectId"=>100},
                               {"createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"open", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d2.id, "type"=>"decision", "pastFlags"=>[], "decider"=>"PaymentDecider", "subjectKlass"=>"PaymentTerm", "subjectId"=>100}]
      json_response.count.should == 2
      json_response.map {|obj| obj["id"] }.should == [@d1, @d2].map(&:id).map(&:to_s)
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000/events"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}/events"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/id/tree" do
    it "returns a tree of the workflow with valid params" do
      get "/workflows/#{@wf.id}/tree"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"id"=>@wf.id, "type"=>"workflow", "name"=>"WFType", "status"=>"open", "children"=>[{"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"enqueued"},
                                                                                                                  {"id"=>@d2.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"open"}]}
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/id/big_tree" do
    it "returns a big_tree of the workflow with valid params" do
      get "/workflows/#{@wf.id}/big_tree"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"createdAt"=>Time.now.to_datetime.to_s, "decider"=>"PaymentDecider", "errorWorkflow"=>false, "mode"=>"blocking", "name"=>"WFType", "parentId"=>nil, "status"=>"open", "subjectId"=>100, "subjectKlass"=>"PaymentTerm", "updatedAt"=>Time.now.to_datetime.to_s, "userId"=>@wf.user.id, "workflowId"=>nil, "workflowType"=>"WFType", "id"=>@wf.id, "type"=>"workflow", "children"=>[{"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"enqueued"},
                                                                                                                                                                                                                                                                                                                                                                                                              {"id"=>@d2.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"open"}]}
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/workflow_id/events/id/tree" do
    it "returns a tree of the event with valid params" do
      get "/workflows/#{@wf.id}/events/#{@d1.id}/tree"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"enqueued"}
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000/events/#{@d1.id}/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if the event is not found" do
      get "/workflows/#{@wf.id}/events/1000/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Event with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}/events/#{@d1.id}/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/workflow_id/events/id/big_tree" do
    it "returns a big_tree of the event with valid params" do
      get "/workflows/#{@wf.id}/events/#{@d1.id}/big_tree"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"enqueued", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "pastFlags"=>[], "decider"=>"PaymentDecider", "subjectKlass"=>"PaymentTerm", "subjectId"=>100}
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000/events/#{@d1.id}/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if the event is not found" do
      get "/workflows/#{@wf.id}/events/1000/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Event with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}/events/#{@d1.id}/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /events/id/tree" do
    it "returns a tree of the event with valid params" do
      get "/events/#{@d1.id}/tree"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"enqueued"}
    end

    it "returns a 404 if the event is not found" do
      get "/events/1000/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Event with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access an event that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/events/#{@d1.id}/tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Event with id(#{@d1.id}) not found"}
    end
  end

  context "GET /events/id/big_tree" do
    it "returns a big_tree of the event with valid params" do
      get "/events/#{@d1.id}/big_tree"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"enqueued", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "pastFlags"=>[], "decider"=>"PaymentDecider", "subjectKlass"=>"PaymentTerm", "subjectId"=>100}
    end

    it "returns a 404 if the event is not found" do
      get "/events/1000/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Event with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access an event that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/events/#{@d1.id}/big_tree"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Event with id(#{@d1.id}) not found"}
    end
  end

end

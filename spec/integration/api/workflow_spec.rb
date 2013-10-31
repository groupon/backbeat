require 'spec_helper'

describe Api::Workflow do
  include Rack::Test::Methods

  deploy BACKBEAT_APP

  def app
    FullRackApp
  end

  let(:user) { FactoryGirl.create(:user) }

  before do
    header 'CLIENT_ID', RSPEC_CONSTANT_USER_CLIENT_ID
    WorkflowServer::Client.stub(:make_decision)

    @wf = FactoryGirl.create(:workflow, user: user)
    @d1 = FactoryGirl.create(:decision, workflow: @wf)
    @d2 = FactoryGirl.create(:decision, workflow: @wf)
    @user = FactoryGirl.create(:user, id: UUIDTools::UUID.random_create.to_s)
  end

  context "POST /workflows" do
    it "returns 401 without the client it header" do
      header 'CLIENT_ID', '12'
      response = post '/workflows'
      response.status.should == 401
      response.body.should == "Unauthorized"
    end

    it "returns 400 when one of the required params is missing" do
      response = post '/workflows'
      response.status.should == 400
      JSON.parse(response.body).should == {"error" => {"name"=>["can't be blank"], "workflowType"=>["can't be blank"], "subject"=>["can't be blank"], "decider"=>["can't be blank"]}}
    end

    it "returns 201 and creates a new workflow when all parameters present" do
      response = post '/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}
      response.status.should == 201
      json_response = JSON.parse(response.body)
      wf_in_db = WorkflowServer::Models::Workflow.find(json_response['id'])
      wf_in_db.should_not be_nil
      wf_in_db.subject.should == {"subject_klass" => "PaymentTerm", "subject_id" => "100"}
    end

    it "returns workflow from database if it already exists" do
      response = post '/workflows', {'workflow_type'=>@wf.workflow_type, 'subject'=>{subject_klass: "PaymentTerm", subject_id: 100}, 'decider'=>@wf.decider}
      response.status.should == 201
      json_response = JSON.parse(response.body)
      new_wf = json_response
      @wf.id.to_s.should == new_wf['id']
    end
  end

  context "PUT /workflows" do
    it "returns an empty array when no workflow matches" do
      response = put '/workflows', workflow_type: "WT1", subject: {subject_klass: "PT1", subject_id: 1}, decider: "D1"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.should be_empty
    end
    it "returns all the workflows for the user" do
      @wf1 = FactoryGirl.create(:workflow, user: @user)
      @wf2 = FactoryGirl.create(:workflow, user: @user)
      header 'CLIENT_ID', @user.id
      response = put '/workflows'
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.map{|wf| wf['id'] }.should == [@wf1.id, @wf2.id]
    end
    [:workflow_type, :decider].each do |filter_field|
      it "filters search by the #{filter_field}" do
        @wf1 = FactoryGirl.create(:workflow, filter_field => "123", user: user)
        @wf2 = FactoryGirl.create(:workflow, filter_field => "789", user: user)
        response = put '/workflows', filter_field => "123"
        response.status.should == 200
        json_response = JSON.parse(response.body)
        json_response.size.should == 1
        json_response.first['id'].should == @wf1.id

        response = put '/workflows', filter_field => "789"
        response.status.should == 200
        json_response = JSON.parse(response.body)
        json_response.size.should == 1
        json_response.first['id'].should == @wf2.id
      end
    end
    it "filters search by the subject" do
      @wf1 = FactoryGirl.create(:workflow, subject: {"subject_klass"=>"Klass", "subject_id"=>"123"}, user: user)
      @wf2 = FactoryGirl.create(:workflow, subject: {"subject_klass"=>"Klass", "subject_id"=>"789"}, user: user)
      response = put '/workflows', subject: {subject_klass: "Klass", subject_id: 123}
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.size.should == 1
      json_response.first['id'].should == @wf1.id

      response = put '/workflows', subject: {subject_klass: "Klass", subject_id: 789}
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.size.should == 1
      json_response.first['id'].should == @wf2.id
    end
    it "works across combination of search parameters" do
      @wf1 = FactoryGirl.create(:workflow, workflow_type: "WT1", subject: {subject_klass: "PT1", subject_id: "1"}, decider: "D1", user: user)
      @wf2 = FactoryGirl.create(:workflow, workflow_type: "WT2", subject: {subject_klass: "PT2", subject_id: "2"}, decider: "D2", user: user)
      response = put '/workflows', workflow_type: "WT1", subject: {subject_klass: "PT1", subject_id: "1"}, decider: "D1"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.size.should == 1
      json_response.first['id'].should == @wf1.id
    end
  end

  context "POST /workflows/id/signal/name" do
    it "returns 404 when workflow not found" do
      response = post "/workflows/1000/signal/test"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    remote_describe "inside jboss container" do
      it "returns 201 and the signal json if workflow exists" do
        wf = FactoryGirl.create(:workflow, user: user)

        response = post "/workflows/#{wf.id}/signal/test", options: { client_data: {data: '123'}, client_metadata: {metadata: '456'} }

        WorkflowServer::Workers::SidekiqJobWorker.drain

        response.status.should == 201
        signal = JSON.parse(response.body)

        wf.reload
        wf.signals.first.id.to_s.should == signal['id']
        wf.signals.first.client_data.should == {'data' => '123'}
        wf.signals.first.client_metadata.should == {'metadata' => '456'}
        decision = wf.signals.first.children.first
        decision.name.should == :test
        decision.status.should == :sent_to_client
      end
    end

    it "returns 400 if the workflow is closed for events" do
      @wf.update_attributes(status: :complete)
      response = post "/workflows/#{@wf.id}/signal/test"
      response.status.should == 400
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) is already complete"}
    end

    it "returns a 404 if a user tries to send a signal to a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      response = post "/workflows/#{@wf.id}/signal/test"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end

    it "returns 400 if the options is not a hash" do
      response = post "/workflows/#{@wf.id}/signal/test", {options: "some_string"}
      response.status.should == 400
      json_response = JSON.parse(response.body)
      json_response["error"].should == "options is invalid"
    end
  end

  context "GET /workflows/id" do
    it "returns a workflow object with valid params" do
      response = get "/workflows/#{@wf.id}"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.should == {"clientData" => {}, "createdAt"=>FORMAT_TIME.call(Time.now.utc), "decider"=>"PaymentDecider", "mode"=>"blocking", "name"=>"WFType", "parentId"=>nil, "status"=>"open", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}, "updatedAt"=>FORMAT_TIME.call(Time.now.utc), "workflowId"=>nil, "workflowType"=>"WFType", "id"=>@wf.id, "type"=>"workflow"}
      json_response['id'].should == @wf.id.to_s
    end

    it "returns a 404 if the workflow is not found" do
      response = get "/workflows/1000"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      response = get "/workflows/#{@wf.id}"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/id/events" do
    it "returns a workflow object with valid params" do
      response = get "/workflows/#{@wf.id}/events"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.should == [{"clientData" => {}, "createdAt"=>FORMAT_TIME.call(Time.now.utc), "name"=>"WFDecision", "parentId"=>nil, "status"=>"open", "updatedAt"=>FORMAT_TIME.call(Time.now.utc), "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "decider"=>"PaymentDecider", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}},
                               {"clientData" => {}, "createdAt"=>FORMAT_TIME.call(Time.now.utc), "name"=>"WFDecision", "parentId"=>nil, "status"=>"open", "updatedAt"=>FORMAT_TIME.call(Time.now.utc), "workflowId"=>@wf.id, "id"=>@d2.id, "type"=>"decision", "decider"=>"PaymentDecider", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}}]
      json_response.count.should == 2
      json_response.map {|obj| obj["id"] }.should == [@d1, @d2].map(&:id).map(&:to_s)
    end

    it "filters by status" do
      @wf.events.first.update_attributes!(status: :something_unknown)
      response = get "/workflows/#{@wf.id}/events?status=something_unknown"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.should == [{"clientData" => {}, "createdAt"=>FORMAT_TIME.call(Time.now.utc), "name"=>"WFDecision", "parentId"=>nil, "status"=>"something_unknown", "updatedAt"=>FORMAT_TIME.call(Time.now.utc), "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "decider"=>"PaymentDecider", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}}]
      json_response.count.should == 1
      json_response.map {|obj| obj["id"] }.should == [@d1].map(&:id).map(&:to_s)
    end

    it "returns a 404 if the workflow is not found" do
      response = get "/workflows/1000/events"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      response = get "/workflows/#{@wf.id}/events"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/id/tree" do
    it "returns a tree of the workflow with valid params" do
      response = get "/workflows/#{@wf.id}/tree"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response.should == {"id"=>@wf.id, "type"=>"workflow", "name"=>"WFType", "status"=>"open", "children"=>[{"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"open"},
                                                                                                                  {"id"=>@d2.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"open"}]}
    end

    it "returns a 404 if the workflow is not found" do
      response = get "/workflows/1000/tree"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      response = get "/workflows/#{@wf.id}/tree"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "GET /workflows/:id/tree/print" do
    it "returns a tree of the workflow with valid params" do
      response = get "/workflows/#{@wf.id}/tree/print"
      response.status.should == 200
      json_response = JSON.parse(response.body)
      json_response["print"].should be_a(String)
    end

    it "returns a 404 if the workflow is not found" do
      response = get "/workflows/1000/tree/print"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      response = get "/workflows/#{@wf.id}/tree/print"
      response.status.should == 404
      json_response = JSON.parse(response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "PUT /workflows/:id/pause" do
    context 'errors' do
      it 'returns 400 when trying to pause a closed workflow' do
        @wf.update_status!(:complete)
        response = put "/workflows/#{@wf.id}/pause"
        response.status.should == 400
        json_response = JSON.parse(response.body)
        json_response.should == {"error" => "A workflow cannot be paused while in complete state"}
      end
    end
    context 'pause' do
      before do
        WorkflowServer::Client.stub(:notify_of)
        @a1 = FactoryGirl.create(:activity, workflow: @wf)
        @d1.async_jobs.map(&:payload_object).map(&:perform) # this runs the schedule_next_event job
        @a1.start
      end
      it 'pauses the workflow' do
        @wf.events.where(status: :pause).count.should == 0
        response = put "/workflows/#{@wf.id}/pause"
        response.status.should == 200
        @wf.reload
        @wf.paused?.should == true
        @a1.send :send_to_client
        @d1.send :send_to_client
        @wf.events.where(status: :pause).count.should == 2
        @wf.events.where(status: :pause).map(&:id).should include(@d1.id)
        @wf.events.where(status: :pause).map(&:id).should include(@a1.id)
        @wf.status.should == :pause
      end
    end
  end

  context "PUT /workflows/:id/resume" do
    context 'errors' do
      it 'returns 400 when trying to resume an unpaused workflow' do
        response = put "/workflows/#{@wf.id}/resume"
        response.status.should == 400
        json_response = JSON.parse(response.body)
        json_response.should == {"error" => "A workflow cannot be resumed unless it is paused"}
      end
    end
    context 'resume' do
      before do
        WorkflowServer::Client.stub(:notify_of)
        @a1 = FactoryGirl.create(:activity, workflow: @wf, status: :pause)
        @d1.update_status!(:pause)
        @wf.update_status!(:pause)
      end
      it 'resumes the workflow and the paused events' do
        @wf.events.where(status: :pause).count.should == 2
        WorkflowServer::Client.should_receive(:make_decision).with(@d1)
        WorkflowServer::Client.should_receive(:perform_activity).with(@a1)

        response = put "/workflows/#{@wf.id}/resume"
        response.status.should == 200
        @wf.reload
        @wf.status.should == :open
        @wf.events.where(status: :pause).count.should == 0
      end
    end
  end
end

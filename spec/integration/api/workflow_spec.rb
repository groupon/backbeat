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
      post '/workflows'
      last_response.status.should == 401
      last_response.body.should == "Unauthorized"
    end

    it "returns 400 when one of the required params is missing" do
      post '/workflows'
      last_response.status.should == 400
      JSON.parse(last_response.body).should == {"error" => {"name"=>["can't be blank"], "workflowType"=>["can't be blank"], "subject"=>["can't be blank"], "decider"=>["can't be blank"]}}
    end

    it "returns 201 and creates a new workflow when all parameters present" do
      post '/workflows', {workflow_type: "WFType", subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "PaymentDecider"}
      last_response.status.should == 201
      json_response = JSON.parse(last_response.body)
      new_wf = json_response
      wf_in_db = WorkflowServer::Models::Workflow.last
      wf_in_db.id.to_s.should == new_wf['id']
    end

    it "returns workflow from database if it already exists" do
      post '/workflows', {'workflow_type'=>@wf.workflow_type, 'subject'=>@wf.subject, 'decider'=>@wf.decider}
      last_response.status.should == 201
      json_response = JSON.parse(last_response.body)
      new_wf = json_response
      @wf.id.to_s.should == new_wf['id']
    end
  end

  context "PUT /workflows" do
    it "returns an empty array when no workflow matches" do
      put '/workflows', workflow_type: "WT1", subject: {subject_klass: "PT1", subject_id: 1}, decider: "D1"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should be_empty
    end
    it "returns all the workflows for the user" do
      @wf1 = FactoryGirl.create(:workflow, user: @user)
      @wf2 = FactoryGirl.create(:workflow, user: @user)
      header 'CLIENT_ID', @user.id
      put '/workflows'
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.map{|wf| wf['id'] }.should == [@wf1.id, @wf2.id]
    end
    [:workflow_type, :decider].each do |filter_field|
      it "filters search by the #{filter_field}" do
        @wf1 = FactoryGirl.create(:workflow, filter_field => "123", user: user)
        @wf2 = FactoryGirl.create(:workflow, filter_field => "789", user: user)
        put '/workflows', filter_field => "123"
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response.size.should == 1
        json_response.first['id'].should == @wf1.id

        put '/workflows', filter_field => "789"
        last_response.status.should == 200
        json_response = JSON.parse(last_response.body)
        json_response.size.should == 1
        json_response.first['id'].should == @wf2.id
      end
    end
    it "filters search by the subject" do
      @wf1 = FactoryGirl.create(:workflow, subject: {"subject_klass"=>"Klass", "subject_id"=>"123"}, user: user)
      @wf2 = FactoryGirl.create(:workflow, subject: {"subject_klass"=>"Klass", "subject_id"=>"789"}, user: user)
      put '/workflows', subject: {subject_klass: "Klass", subject_id: 123}
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.size.should == 1
      json_response.first['id'].should == @wf1.id

      put '/workflows', subject: {subject_klass: "Klass", subject_id: 789}
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.size.should == 1
      json_response.first['id'].should == @wf2.id
    end
    it "works across combination of search parameters" do
      @wf1 = FactoryGirl.create(:workflow, workflow_type: "WT1", subject: {subject_klass: "PT1", subject_id: "1"}, decider: "D1", user: user)
      @wf2 = FactoryGirl.create(:workflow, workflow_type: "WT2", subject: {subject_klass: "PT2", subject_id: "2"}, decider: "D2", user: user)
      put '/workflows', workflow_type: "WT1", subject: {subject_klass: "PT1", subject_id: "1"}, decider: "D1"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.size.should == 1
      json_response.first['id'].should == @wf1.id
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
      wf = FactoryGirl.create(:workflow, user: user)

      post "/workflows/#{wf.id}/signal/test", options: { client_data: {data: '123'}, client_metadata: {metadata: '456'} }

      last_response.status.should == 201
      signal = JSON.parse(last_response.body)

      wf.reload
      wf.signals.first.id.to_s.should == signal['id']
      wf.signals.first.client_data.should == {'data' => '123'}
      wf.signals.first.client_metadata.should == {'metadata' => '456'}
      decision = wf.signals.first.children.first
      decision.name.should == :test
      #TODO: @naren, please check this change
      # decision.status.should == :sent_to_client
      decision.status.should == :open
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

    it "returns 400 if the options is not a hash" do
      post "/workflows/#{@wf.id}/signal/test", {options: "some_string"}
      last_response.status.should == 400
      json_response = JSON.parse(last_response.body)
      json_response["error"].should == "invalid parameter: options"
    end
  end

  context "GET /workflows/id" do
    it "returns a workflow object with valid params" do
      get "/workflows/#{@wf.id}"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response.should == {"clientData" => {}, "createdAt"=>Time.now.to_datetime.to_s, "decider"=>"PaymentDecider", "mode"=>"blocking", "name"=>"WFType", "parentId"=>nil, "status"=>"open", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}, "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>nil, "workflowType"=>"WFType", "id"=>@wf.id, "type"=>"workflow"}
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
      #TODO: @naren, please check this change
      # json_response.should == [{"clientData" => {}, "createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"open", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "decider"=>"PaymentDecider", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}},
      json_response.should == [{"clientData" => {}, "createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"sent_to_client", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d1.id, "type"=>"decision", "decider"=>"PaymentDecider", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}},
                               {"clientData" => {}, "createdAt"=>Time.now.to_datetime.to_s, "name"=>"WFDecision", "parentId"=>nil, "status"=>"open", "updatedAt"=>Time.now.to_datetime.to_s, "workflowId"=>@wf.id, "id"=>@d2.id, "type"=>"decision", "decider"=>"PaymentDecider", "subject"=>{"subjectKlass"=>"PaymentTerm", "subjectId"=>"100"}}]
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
      #TODO: @naren, please check this change
      # json_response.should == {"id"=>@wf.id, "type"=>"workflow", "name"=>"WFType", "status"=>"open", "children"=>[{"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"open"},
      json_response.should == {"id"=>@wf.id, "type"=>"workflow", "name"=>"WFType", "status"=>"open", "children"=>[{"id"=>@d1.id, "type"=>"decision", "name"=>"WFDecision", "status"=>"sent_to_client"},
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

  context "GET /workflows/:id/tree/print" do
    it "returns a tree of the workflow with valid params" do
      get "/workflows/#{@wf.id}/tree/print"
      last_response.status.should == 200
      json_response = JSON.parse(last_response.body)
      json_response["print"].should be_a(String)
    end

    it "returns a 404 if the workflow is not found" do
      get "/workflows/1000/tree/print"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(1000) not found"}
    end

    it "returns a 404 if a user tries to access a workflow that doesn't belong to them" do
      header 'CLIENT_ID', @user.id
      get "/workflows/#{@wf.id}/tree/print"
      last_response.status.should == 404
      json_response = JSON.parse(last_response.body)
      json_response.should == {"error" => "Workflow with id(#{@wf.id}) not found"}
    end
  end

  context "PUT /workflows/:id/pause" do
    context 'errors' do
      it 'returns 400 when trying to pause a closed workflow' do
        @wf.update_status!(:complete)
        put "/workflows/#{@wf.id}/pause"
        last_response.status.should == 400
        json_response = JSON.parse(last_response.body)
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
        put "/workflows/#{@wf.id}/pause"
        last_response.status.should == 200
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
        put "/workflows/#{@wf.id}/resume"
        last_response.status.should == 400
        json_response = JSON.parse(last_response.body)
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

        put "/workflows/#{@wf.id}/resume"
        last_response.status.should == 200
        @wf.reload
        @wf.status.should == :open
        @wf.events.where(status: :pause).count.should == 0
      end
    end
  end
end
require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Workflow do
  before do
    @event_klass = WorkflowServer::Models::Workflow
    @event_data = {name: :test_flag, workflow_type: :wf_type, subject_klass: "PaymentTerm", subject_id: 100, decider: "A::B::C", user: FactoryGirl.create(:user) }
    @wf = FactoryGirl.create(:workflow)
    @event = @wf
  end

  it_should_behave_like 'events'

  [:workflow_type, :subject_klass, :subject_id, :decider, :user].each do |field|
    it "validates presence of #{field}" do
      @event_data.delete(field)
      wf = WorkflowServer::Models::Workflow.new(@event_data)
      wf.valid?.should == false
      wf.errors.messages.should == {field => ["can't be blank"]}
    end
  end

  context "#signal" do
    it "raises an error if status is complete" do
      @wf.update_status!(:complete)
      expect {
        @wf.signal(:something)
      }.to raise_error(WorkflowServer::EventComplete, "Workflow with id(#{@wf.id}) is already complete")
    end
  end

  context "#completed" do
    it "goes in complete state" do
      @wf.completed
      @wf.status.should == :complete
    end
    it "drops a signal / decision task to notify the workflow" do
      workflow = FactoryGirl.create(:workflow)
      @wf.update_attributes!(workflow: workflow)
      @wf.completed                              
      workflow.signals.count.should == 1
      workflow.decisions.count.should == 1
      decision = workflow.decisions.first
      decision.name.should == "#{@wf.name}_succeeded".to_sym
    end
  end

  context "#errored" do
    it "goes in error state" do
      @wf.errored(:some_error)
      @wf.status.should == :error
    end
    it "drops a signal / decision task to notify the workflow" do
      workflow = FactoryGirl.create(:workflow)
      @wf.update_attributes!(workflow: workflow)
      @wf.errored(:some_error)                              
      workflow.signals.count.should == 1
      workflow.decisions.count.should == 1
      decision = workflow.decisions.first
      decision.name.should == "#{@wf.name}_errored".to_sym
    end
  end

  context "#start" do
    it "updates the status to executing" do
      @wf.start
      @wf.status.should == :executing
      @wf.signals.count.should == 0
    end
    it "drops a signal if called with a start signal" do
      wf = FactoryGirl.create(:workflow, start_signal: :some_signal)
      wf.start
      wf.signals.count.should == 1
      signal = wf.signals.first
      signal.name.should == :some_signal
    end
  end
end
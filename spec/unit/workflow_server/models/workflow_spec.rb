require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Workflow do

  let(:user) { FactoryGirl.create(:user) }

  before do
    @event_klass = WorkflowServer::Models::Workflow
    @event_data = {name: :test_flag, workflow_type: :wf_type, subject: {subject_klass: "PaymentTerm", subject_id: 100}, decider: "A::B::C", user: user }
    @wf = FactoryGirl.create(:workflow, user: user)
    @event = @wf
  end

  it_should_behave_like 'events'

  [:workflow_type, :subject, :decider, :user].each do |field|
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
      workflow = FactoryGirl.create(:workflow, user: user)
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
      workflow = FactoryGirl.create(:workflow, user: user)
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
      wf = FactoryGirl.create(:workflow, start_signal: :some_signal, user: user)
      wf.start
      wf.signals.count.should == 1
      signal = wf.signals.first
      signal.name.should == :some_signal
    end
  end

  context '#pause' do
    [:complete, :anything_else].each do |new_status|
      it "raises error when paused in #{new_status} state" do
        @wf.update_status!(new_status)
        expect {
          @wf.pause
        }.to raise_error(WorkflowServer::InvalidEventStatus, "A workflow cannot be paused while in #{new_status} state")
      end
    end
    [:open, :pause].each do |new_status|
      it 'updates status to paused' do
        @wf.update_status!(new_status)
        @wf.pause
        @wf.status.should == :pause
      end
    end
  end

  context '#resume' do
    it 'raises error if status is not paused' do
      @wf.update_status!(:open)
      expect {
        @wf.resume
      }.to raise_error(WorkflowServer::InvalidEventStatus, "A workflow cannot be resumed unless it is paused")
    end
    it 'calls resumed' do
      @wf.update_status!(:pause)
      @wf.should_receive(:resumed)
      @wf.resume
    end
  end

  context '#resumed' do
    before do
      @wf.update_status!(:pause)
      @wf.stub(:with_lock).and_yield
    end
    it 'updates status to open' do
      @wf.resumed
      @wf.status.should == :open
    end
    it 'calls resumed on the paused events' do
      @wf.should_receive(:update_status!).with(:open)
      events = [mock('1', resumed: nil), mock('2', resumed: nil)]
      @wf.stub_chain(:events, :where => events)
      events.each { |e| e.should_receive(:resumed) }
      @wf.resumed
    end
  end
end
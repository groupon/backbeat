require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Signal do
  before do
    @event_klass = WorkflowServer::Models::Signal
    @event_data = {name: :test_sig}
    @event = FactoryGirl.create(:signal)
  end

  it_should_behave_like 'events'

  it "calls start on create" do
    signal = WorkflowServer::Models::Signal.new(@event_data)
    signal.should_receive(:start)
    signal.save!
  end

  context "#start" do
    before do
      @signal = FactoryGirl.create(:signal, status: :open)
    end
    it "handles start - puts a decision task and goes into completed state" do
      @signal.reload
      @signal.status.should == :complete
      @signal.children.count.should == 1
      child = @signal.children.first
      child.should be_instance_of(WorkflowServer::Models::Decision)
      child.name.should == @signal.name
    end
  end
end
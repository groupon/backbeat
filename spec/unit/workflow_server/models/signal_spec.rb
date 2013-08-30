require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Signal do

  let(:user) { FactoryGirl.create(:user) }
  let(:workflow) { FactoryGirl.create(:workflow, user: user) }

  deploy BACKBEAT_APP

  before do
    @event_klass = WorkflowServer::Models::Signal
    @event_data = {name: :test_sig}
    @event = FactoryGirl.create(:signal, workflow: workflow)
  end

  it_should_behave_like 'events'

  context "#start" do
    before do
      @signal = FactoryGirl.create(:signal, status: :open, workflow: workflow)
    end
    it "handles start - puts a decision task and goes into completed state" do
      @signal.start
      @signal.reload
      @signal.status.should == :complete
      @signal.children.count.should == 1
      child = @signal.children.first
      child.should be_instance_of(WorkflowServer::Models::Decision)
      child.name.should == @signal.name
    end
  end
end
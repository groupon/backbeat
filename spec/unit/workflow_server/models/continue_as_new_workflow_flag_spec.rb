require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::ContinueAsNewWorkflowFlag do
  before do
    @event_klass = WorkflowServer::Models::ContinueAsNewWorkflowFlag
    @event_data = {name: :test_flag}
    @flag = FactoryGirl.create(:continue_as_new_workflow_flag, status: :open)
    @event = @flag
  end

  it 'marks past events as complete and inactive, destroys all async jobs on them' do
    past_events = [ mock('event1', cleanup: nil), mock('event2', cleanup: nil) ]
    @event.workflow.should_receive(:events).and_return(past_events)
    past_events.should_receive(:where).with(:sequence.lt => @event.sequence).and_return(past_events)
    past_events.should_receive(:update_all).with(status: :complete, inactive: true)
    past_events.each { |event| event.should_receive(:cleanup) }
    @event.start
  end

  it_should_behave_like 'events'
end
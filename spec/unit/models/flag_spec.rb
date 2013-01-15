require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Flag do
  before do
    @event_klass = WorkflowServer::Models::Flag
    @event_data = {name: :test_flag}
  end

  it_should_behave_like 'events'

  it "goes into complete start on start" do
    flag = FactoryGirl.create(:flag, status: :open)
    flag.reload
    flag.status.should == :open
    flag.start
    flag.status.should == :complete
  end
end
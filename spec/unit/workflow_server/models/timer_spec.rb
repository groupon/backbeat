require 'spec_helper'
require_relative 'event_se'

describe WorkflowServer::Models::Timer do
  before do
    @event_klass = WorkflowServer::Models::Timer
    @event_data = {name: :test_timer, fires_at: Date.tomorrow}
  end

  it_should_behave_like 'events'

  context "#validation" do
    it "fires_at parameter is mandatory" do
      @event_data.delete(:fires_at)
      timer = @event_klass.new(@event_data)
      timer.valid?.should == false
      timer.errors[:fires_at].should == ["can't be blank"]
    end
  end

  context "#start" do
    it "updates the status to executing and schedules a delayed job to go at the" do
      timer = FactoryGirl.create(:timer, fires_at: Date.tomorrow)
      timer.status.should == :open
      timer.start
      timer.status.should == :executing
      job = Delayed::Job.last
      handler = YAML.load(job.handler)
      handler['_id'].should == timer.id
      job.run_at.should == Date.tomorrow.to_time
    end
  end

  context "#fire" do
    it "schedules a decision task" do
      timer = FactoryGirl.create(:timer, fires_at: Date.tomorrow)
      timer.children.count.should == 0
      timer.fire
      timer.status.should == :complete
      timer.children.count.should == 1
      child = timer.children.first
      child.should be_instance_of(WorkflowServer::Models::Decision)
      child.name.should == timer.name
    end
  end
end
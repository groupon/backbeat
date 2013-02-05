require 'spec_helper'

shared_examples_for 'events' do
  it "name is mandatory" do
    event = @event_klass.new
    event.valid?.should == false
    event.errors.messages[:name].should == ["can't be blank"]
  end

  it "delayed jobs are deleted" do
    5.times do
      WorkflowServer::Async::Job.schedule({event: @event, method: :fire, max_attempts: 5}, Date.tomorrow) 
    end
    @event.async_jobs.and(handler: /fire/).count.should == 5
    WorkflowServer::Async::Job.jobs(@event).and(handler: /fire/).count.should == 5
    @event.destroy
    WorkflowServer::Async::Job.jobs(@event).count.should == 0
  end
end
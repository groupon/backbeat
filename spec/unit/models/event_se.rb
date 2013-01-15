require 'spec_helper'

shared_examples_for 'events' do
  it "name is mandatory" do
    event = @event_klass.new
    event.valid?.should == false
    event.errors.messages[:name].should == ["can't be blank"]
  end
end
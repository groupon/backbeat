require 'spec_helper'

describe WorkflowServer::Models::Event do
  describe "#with_lock" do
    it "if a Mongoid::LockError is raised, retry 5 times, then surface the exception" do
      event = WorkflowServer::Models::Event.new
      event.stub(:sleep)

      event.should_receive(:with_lock_without_retry).exactly(6).times.and_raise(Mongoid::LockError.new)
      lambda { event.with_lock({foo: 'bar'}) }.should raise_error(Mongoid::LockError)
    end
  end
end

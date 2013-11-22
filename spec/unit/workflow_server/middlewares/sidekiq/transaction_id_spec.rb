require 'spec_helper'

describe WorkflowServer::Middlewares::TransactionId do
  it "sets the transaction id and then yields" do
    yielded = false
    WorkflowServer::Logger.tid.should be_nil
    subject.call do
      WorkflowServer::Logger.tid.should_not be_nil
      yielded = true
    end
    WorkflowServer::Logger.tid.should be_nil
    yielded.should == true
  end
end
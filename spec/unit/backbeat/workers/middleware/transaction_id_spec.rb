require 'spec_helper'

describe Backbeat::Workers::Middleware::TransactionId do
  it "sets the transaction id and then yields" do
    yielded = false
    Backbeat::Logging.tid.should be_nil
    subject.call do
      Backbeat::Logging.tid.should_not be_nil
      yielded = true
    end
    Backbeat::Logging.tid.should be_nil
    yielded.should == true
  end
end

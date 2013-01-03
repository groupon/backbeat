require 'spec_helper'

describe Backbeat::Workers::Middleware::TransactionId do
  it "sets the transaction id and then yields" do
    yielded = false
    expect(Backbeat::Logger.tid).to be_nil
    subject.call do
      expect(Backbeat::Logger.tid).not_to be_nil
      yielded = true
    end
    expect(Backbeat::Logger.tid).to be_nil
    expect(yielded).to eq(true)
  end
end

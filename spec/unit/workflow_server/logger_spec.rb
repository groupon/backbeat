# encoding: UTF-8
require 'spec_helper'

class TestLogger
  extend WorkflowServer::Logger
end
describe WorkflowServer::Logger do
  it "should handle multiple string encodings" do
    test_message = "Rüby".encode("ASCII-8BIT")
    expect {
      TestLogger.debug(test_message)
    }.to_not raise_error
  end
end

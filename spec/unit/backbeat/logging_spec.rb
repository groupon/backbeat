# encoding: UTF-8
require 'spec_helper'

describe Backbeat::Logger do
  class TestLogger
    extend Backbeat::Logging
  end

  it "should handle multiple string encodings" do
    if RUBY_PLATFORM == "java"
      test_message = "Rüby".encode("ASCII-8BIT")
      expect {
        TestLogger.debug(test_message)
      }.to_not raise_error
    end
  end
end

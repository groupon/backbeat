# encoding: UTF-8
require 'spec_helper'

describe Backbeat::Logger do
  class TestLogger
    extend Backbeat::Logging
  end

  it "logs the revision sha" do
    allow(Backbeat::Config).to receive(:revision).and_return("fake_sha")

    expect(Backbeat::Logger).to receive(:log) do |level, message|
      expect(JSON.parse(message)["revision"]).to eq("fake_sha")
    end

    TestLogger.debug("message")
  end

  xit "should handle multiple string encodings" do
    test_message = "Rüby".encode("ASCII-8BIT")
    expect {
      TestLogger.debug(test_message)
    }.to_not raise_error
  end
end

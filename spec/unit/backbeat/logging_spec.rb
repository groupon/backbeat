# encoding: UTF-8
require 'spec_helper'

describe Backbeat::Logger do
  class TestLogger
    extend Backbeat::Logging
  end

  before do
    class Backbeat::Config
      @revision = nil
    end
  end

  it "logs the revision sha if it exists" do
    allow(File).to receive(:exists?).and_return(true)
    allow(File).to receive(:read).and_return("fake_sha")
    expect(Backbeat::Logger).to receive(:log) do |level, message|
      expect(JSON.parse(message)["revision"]).to eq("fake_sha")
    end

    TestLogger.debug("message")
  end

  it "logs the revision as nil if the file does not exist" do
    allow(File).to receive(:exists?).and_return(false)
    expect(Backbeat::Logger).to receive(:log) do |level, message|
      expect(JSON.parse(message)["revision"]).to eq(nil)
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

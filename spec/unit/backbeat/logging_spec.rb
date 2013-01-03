# encoding: UTF-8
require 'spec_helper'

describe Backbeat::Logger do
  class TestLogger
    extend Backbeat::Logging
  end

  it "logs the revision sha" do
    allow(Backbeat::Config).to receive(:revision).and_return("fake_sha")

    expect(Backbeat::Logger).to receive(:add) do |level, message|
      expect(message[:revision]).to eq("fake_sha")
    end

    TestLogger.debug({ message: "message" })
  end

  it "does not log below the configured log severity level" do
    logs = StringIO.new
    logger = ::Logger.new(logs)
    logger.level = ::Logger::WARN
    Backbeat::Logger.logger = logger

    Backbeat::Logger.info({ message: 'Hello' })

    expect(logs.size).to eq(0)

    Backbeat::Logger.fatal({ message: 'Goodbye' })

    expect(logs.size).to be > 0
  end

  xit "should handle multiple string encodings" do
    test_message = "Rüby".encode("ASCII-8BIT")
    expect {
      TestLogger.debug(test_message)
    }.to_not raise_error
  end
end

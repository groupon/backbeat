require "spec_helper"
require "stringio"

describe Backbeat::Instrument do
  let(:log) { StringIO.new }

  before do
    Backbeat::Logger.logger = ::Logger.new(log)
  end

  it "logs a started message" do
    Backbeat::Instrument.instrument("event", 1) do
      :done
    end

    expect(log.string).to include("started")
  end

  it "runs the block" do
    x = 1

    Backbeat::Instrument.instrument("event", 1) do
      x += 1
    end

    expect(x).to eq(2)
  end

  it "logs a succeeded message" do
    Backbeat::Instrument.instrument("event", 1) do
      :done
    end

    expect(log.string).to include("succeeded")
  end

  it "logs an error message" do
    begin
      Backbeat::Instrument.instrument("event", 1) do
        raise "Error"
      end
    rescue
    end

    expect(log.string).to include("errored")
  end

  it "logs a fallback message" do
    bad_error = Class.new(StandardError) do
      def to_s
        raise "Nope"
      end
    end

    begin
      Backbeat::Instrument.instrument("event", 1) do
        raise bad_error
      end
    rescue
    end

    expect(log.string).to include("error_logging_error")
  end
end

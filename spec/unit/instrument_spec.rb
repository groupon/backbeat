# Copyright (c) 2015, Groupon, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the name of GROUPON nor the names of its contributors may be
# used to endorse or promote products derived from this software without
# specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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

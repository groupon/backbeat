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

require 'spec_helper'

describe Backbeat::Web::Middleware::Heartbeat, :api_test do

  def with_no_heartbeat
    heartbeat = "#{File.dirname(__FILE__)}/../../../../public/heartbeat.txt"
    begin
      File.delete(heartbeat)
      yield
    ensure
      File.open(heartbeat, 'w')
    end
  end

  context "/heartbeat.txt" do
    it "returns 200 if heartbeat present" do
      response = get '/heartbeat.txt'
      expect(response.status).to eq(200)
      expect(response.headers["Content-Type"]).to eq("text/plain")
      expect(response.body).to eq("We have a pulse.")
    end

    it "returns 503 if heartbeat missing" do
      with_no_heartbeat do
        response = get '/heartbeat.txt'
        expect(response.status).to eq(503)
        expect(response.headers["Content-Type"]).to eq("text/plain")
        expect(response.body).to eq("It's dead, Jim.")
      end
    end
  end
end

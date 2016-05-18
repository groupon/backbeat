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

describe Backbeat::Web::Middleware::Log, :api_test do
  let(:user) { FactoryGirl.create(:user) }
  let(:wf) { FactoryGirl.create(:workflow, user: user) }

  before do
    allow(Backbeat::Client).to receive(:make_decision)
  end

  it "includes the transaction id in the response" do
    response = get "v2/workflows/#{wf.id}"
    expect(response.status).to eq(200)
    expect(response.headers.keys).to include("X-backbeat-tid")
  end

  it "logs route details" do
    log_count = 0
    expect(Backbeat::Logger).to receive(:info).twice do |response_info|
      log_count += 1
      if log_count == 2
        expect(response_info).to eq({
          message: "Request Complete",
          request: {
            method: "GET",
            path: "/v2/workflows/#{wf.id}",
            params: {},
            client_id: user.id
          },
          response: {
            status: 200,
            duration: 0.0,
          }
        })
      end
    end
    response = get "v2/workflows/#{wf.id}"
    expect(response.status).to eq(200)
  end
end

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

describe Backbeat::Web::Middleware::CamelCase do
  let(:body) {
    {
      'actor_klass' => "1",
      "actor_id" => 2,
      "nested_body" => { "nested_key" => "dont_touch_values" }
    }
  }
  let(:camelcase_body) {
    {
      "actorKlass" => "1",
      "actorId" => 2,
      "nestedBody" => { "nestedKey" => "dont_touch_values" }
    }
  }

  let(:mock_app) {
    lambda do |env|
      Rack::Response.new(body.to_json, 200, { 'Content-Type' => 'application/json' })
    end
  }

  it "converts response keys to camelCases" do
    request = Rack::MockRequest.new(Rack::Lint.new(described_class.new(mock_app)))

    response = request.get("http://someplace", { params: { abc: 20, def: 500 }})
    parsed_body = JSON.parse(response.body)

    expect(parsed_body).to eq(camelcase_body)
  end

  it "doesn't change the response if content type is not application/json" do
    app = lambda do |env|
      Rack::Response.new(body.to_json, 200, { 'Content-Type' => 'application/xml' })
    end
    request = Rack::MockRequest.new(Rack::Lint.new(described_class.new(app)))

    response = request.get("http://someplace", { params: { abc: 20, def: 500 }})
    parsed_body = JSON.parse(response.body)

    expect(parsed_body).to eq(body)
  end

  it "updates the content length header" do
    request = Rack::MockRequest.new(Rack::Lint.new(described_class.new(mock_app)))

    response = request.get("http://someplace", { params: { abc: 20, def: 500 }})

    expect(response.headers['Content-Length'].to_i).to eq(camelcase_body.to_json.size)
  end
end

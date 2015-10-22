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

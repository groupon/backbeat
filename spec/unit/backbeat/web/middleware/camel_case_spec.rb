require 'spec_helper'

describe Backbeat::Web::Middleware::CamelCase do
  before do
    @env = {}
    @body = {'actor_klass' => "1", "actor_id" => 2, "deep_nest" => {"nested_inside" => "dont_touch_values"}}.to_json
    @updated_body = {"actorKlass"=>"1", "actorId"=>2, "deepNest"=>{"nestedInside"=>"dont_touch_values"}}.to_json
    @mock_app = lambda { |env|
      @env.merge!(env)
      Rack::Response.new(@body, 200, {'Content-Type' => 'application/json'})
    }
  end

  it "converts response keys to camelCases" do
    request = Rack::MockRequest.new(Rack::Lint.new(described_class.new(@mock_app)))
    response = request.get("http://someplace", {params: {abc: 20, bcd_abc: 500}})
    json_response = JSON.parse(response.body)
    expect(json_response).to eq(JSON.parse(@updated_body))
  end

  it "doesn't change the response if content type is not application/json" do
    @mock_app = lambda { |env|
      @env.merge!(env)
      Rack::Response.new(@body, 200, {'Content-Type' => 'application/xml'})
    }
    request = Rack::MockRequest.new(Rack::Lint.new(described_class.new(@mock_app)))
    response = request.get("http://someplace", {params: {abc: 20, bcd_abc: 500}})
    json_response = JSON.parse(response.body)
    expect(json_response).to eq({"actor_klass"=>"1", "actor_id"=>2, "deep_nest"=>{"nested_inside"=>"dont_touch_values"}})
  end

  it "updates the content length header" do
    request = Rack::MockRequest.new(Rack::Lint.new(described_class.new(@mock_app)))
    response = request.get("http://someplace", {params: {abc: 20, bcd_abc: 500}})
    expect(response.headers['Content-Length'].to_i).not_to eq(@body.size)
    expect(response.headers['Content-Length'].to_i).to eq(@updated_body.size)
  end
end

module Api
  class CamelCase
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)
      if headers["Content-Type"] == "application/json"
        begin
          new_body = response.body.map {|str| JSON.parse(str) }
          ::Api::HashKeyTransformations.camelize_keys(new_body)
          response.body = new_body.map(&:to_json)
          headers['Content-Length'] = content_length(response.body, headers)
        rescue Exception => e
        end
      end
      [ status, headers, response ]
    end

    private

    def content_length(body, headers)
      body.inject(0) {|size, str| size += Rack::Utils.bytesize(str) }.to_s
    end

    def chunked?(headers)
      "chunked" == headers['Transfer-Encoding']
    end
  end
end
module Backbeat
  module Web
    module Middleware
      class CamelCase
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, response = @app.call(env)
          if headers['Content-Type'] == 'application/json'
            original_body  = response.body.map { |str| JSON.parse(str) }
            camelized      = Client::HashKeyTransformations.camelize_keys(original_body)
            camelized_json = camelized.map(&:to_json)
            response.body  = camelized_json
            headers['Content-Length'] = content_length(camelized_json)
          end
          [status, headers, response]
        end

        private

        def content_length(body)
          body.reduce(0) do |length, str|
            length += Rack::Utils.bytesize(str)
          end.to_s
        end
      end
    end
  end
end

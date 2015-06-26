module Backbeat
  module Web
    module Middleware
      class CamelCase
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, response = @app.call(env)
          if headers["Content-Type"] == "application/json"
            begin
              new_body = response.body.map { |str| JSON.parse(str) }
              Client::HashKeyTransformations.camelize_keys(new_body)
              response.body = new_body.map(&:to_json)
              headers['Content-Length'] = content_length(response.body, headers)
            rescue Exception => e
            end
          end
          [ status, headers, response ]
        end

        private

        def content_length(body, headers)
          size = 0
          body.each {|str| size += Rack::Utils.bytesize(str) }
          size.to_s
        end

        def chunked?(headers)
          "chunked" == headers['Transfer-Encoding']
        end
      end
    end
  end
end

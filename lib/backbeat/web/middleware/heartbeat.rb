module Backbeat
  module Web
    module Middleware
      class Heartbeat
        def initialize(app)
          @app = app
        end

        ENDPOINT = '/heartbeat.txt'.freeze

        def call(env)
          if env['PATH_INFO'] == ENDPOINT
            if File.exists?("#{File.dirname(__FILE__)}/../../../../public/heartbeat.txt")
              return [200, {"Content-Type" => "text/plain"}, ["We have a pulse."]]
            else
              return [503, {"Content-Type" => "text/plain"}, ["It's dead, Jim."]]
            end
          else
            @app.call(env)
          end
        end
      end
    end
  end
end

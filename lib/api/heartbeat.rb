module Api
  class Heartbeat
    def initialize(app)
      @app = app
    end

    ENDPOINT = '/heartbeat.txt'.freeze
    def call(env)
      if env['PATH_INFO'] == ENDPOINT
        if File.exists?("#{File.dirname(__FILE__)}/../../public/heartbeat.txt")
          return [ 200, {"Content-Type" => "text/plain"}, ["We have a pulse."] ]
        else
          return [ 404, {"Content-Type" => "text/plain"}, ["It's dead, Jim."] ]
        end
      end
      status, headers, body = @app.call(env)
      [status, headers, body]
    end
  end
end

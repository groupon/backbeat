module Api
  class ClearSession
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    ensure
      if defined?(::Mongoid)
        ::Mongoid::IdentityMap.clear
        ::Mongoid.disconnect_sessions
      end
    end
  end
end
module Api
  class CamelCase
    def initialize(app)
      @app = app
    end

    def call(env)
      ap env[:params]
      @app.call(env)
    end
  end
end
module Api
  class CamelJsonFormatter
    class << self

      def call(object, env)
        if !object.is_a?(Hash) && object.respond_to?(:serializable_hash)
          object = object.serializable_hash
        end
        ::Api::HashKeyTransformations.camelize_keys(object)
        ::Grape::Formatter::Json.call(object, env)
      end

    end
  end
end
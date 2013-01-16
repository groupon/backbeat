module Api
  class CamelJsonFormatter
    class << self

      def call(object, env)
        if object.respond_to?(:each)
          object = object.map(&method(:convert_object))
        else
          object = convert_object(object)
        end
        ::Grape::Formatter::Json.call(object, env)
      end

      def convert_object(object)
        if !object.is_a?(Hash) && object.respond_to?(:serializable_hash)
          object = object.serializable_hash
        end
        ::Api::HashKeyTransformations.camelize_keys(object)
        object
      end
    end
  end
end
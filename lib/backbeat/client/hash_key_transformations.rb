module Backbeat
  module Client
    module HashKeyTransformations
      def self.camelize_keys(object)
        transform_keys(object) do |key|
          key.to_s.camelize(:lower).to_sym
        end
      end

      def self.underscore_keys(object)
        transform_keys(object) do |key|
          key.to_s.underscore.to_sym
        end
      end

      def self.transform_keys(object, &block)
        case object
        when Hash
          object.reduce({}) do |memo, (key, value)|
            new_key = block.call(key)
            memo[new_key] = transform_keys(value, &block)
            memo
          end
        when Array
          object.map do |value|
            transform_keys(value, &block)
          end
        else
          if object.respond_to?(:to_hash)
            transform_keys(object.to_hash, &block)
          else
            object
          end
        end
      end
    end
  end
end

module Backbeat
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
      if object.is_a?(Hash)
        object.keys.each do |key|
          new_key = block.call(key)
          if ((object.has_key?(new_key) || object.has_key?(new_key.to_s)) && key.to_sym != new_key)
            raise ("Creating duplicate key(#{new_key.inspect}) by transformation, cannot continue.")
          end

          value = object.delete(key)
          object[new_key] = transform_keys(value, &block)
        end
      elsif object.is_a?(Array)
        object.map! do |value|
          transform_keys(value, &block)
        end
      elsif object.respond_to?(:to_hash)
        return transform_keys(object.to_hash, &block)
      end

      object
    end
  end
end

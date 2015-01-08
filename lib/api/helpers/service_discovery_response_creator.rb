module Api
  module ServiceDiscoveryResponseCreator
    def self.call(model, response_object, specific_fields = nil)
      raise "model doesn't respond to field_hash" unless model.respond_to?(:field_hash)
      field_hash = model.field_hash

      field_hash.each_pair do |field, data|
        next if specific_fields.is_a?(Array) && !specific_fields.include?(field.to_sym)
        options = {}
        options[:description] = data[:label] if data[:label]
        case data[:type].to_s
        when "Integer"
          response_object.integer field.to_sym, options
        when "Float", "BigDecimal"
          response_object.number field.to_sym, options
        when "Array"
          response_object.array(field.to_sym, options) {}
        when "Hash"
          response_object.object(field.to_sym, options) {}
        when "Symbol", "Time", "Object"
          response_object.string field.to_sym, options
        else
          response_object.string field.to_sym, options
        end
      end
    end
  end
end

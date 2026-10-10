# lib/odsl/audit/serializer.rb
require "json"

module Odsl
  module Audit
    module Serializer
      def self.dump(value)
        JSON.generate(serialize(value))
      end

      def self.load(json_string)
        return nil if json_string.nil?
        JSON.parse(json_string)
      end

      def self.serializable?(value)
        dump(value)
        true
      rescue JSON::GeneratorError, TypeError
        false
      end

      def self.serialize(value)
        case value
        when Hash                                          then value.transform_keys(&:to_s).transform_values { |v| serialize(v) }
        when Array                                         then value.map { |v| serialize(v) }
        when Struct                                        then serialize(value.to_h)
        when String, Numeric, TrueClass, FalseClass, NilClass then value
        else raise TypeError, "Cannot serialize #{value.class}"
        end
      end
      private_class_method :serialize
    end
  end
end

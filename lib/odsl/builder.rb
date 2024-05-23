
module Odsl
  class Builder
    class << self
      def build(*modules)
        business_class = begin
          Object.const_get class_name(modules)
        rescue StandardError
          nil
        end
        business_class ||= Object.const_set(class_name(modules), Class.new)

        modules.each do |mod|
          business_class.send(:include, mod)
        end

        business_class
      end

      def class_name(modules)
        "Builder_#{modules.map(&:to_s).join('_')}".gsub('::','_')
      end

      def method_from_bool(mode)
        mode ? :on : :off
      end
    end
  end
end
# lib/odsl/adapters/base.rb
module Odsl
  module Adapters
    class Base
      def self.enqueue(service_class:, method_name:, kwargs:, key: nil, callable: nil)
        raise NotImplementedError,
          "#{self} must implement .enqueue(service_class:, method_name:, kwargs:, key:, callable:)"
      end
    end
  end
end

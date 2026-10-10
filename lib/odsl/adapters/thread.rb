# lib/odsl/adapters/thread.rb
module Odsl
  module Adapters
    class Thread < Base
      def self.enqueue(service_class:, method_name:, kwargs:, key: nil, callable: nil)
        ::Thread.new do
          if callable
            callable.call
          else
            klass = Object.const_get(service_class)
            klass.new(**kwargs.transform_keys(&:to_sym)).run(method_name.to_sym, key: key)
          end
        end
      end
    end
  end
end

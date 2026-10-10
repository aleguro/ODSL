# lib/odsl/adapters/odsl_job.rb
# Only loaded when ActiveJob is available
if defined?(ActiveJob)
  module Odsl
    class OdslJob < ActiveJob::Base
      def perform(service_class:, method_name:, kwargs:, key: nil)
        klass = Object.const_get(service_class)
        klass.new(**kwargs.transform_keys(&:to_sym)).run(method_name.to_sym, key: key)
      end
    end
  end
end

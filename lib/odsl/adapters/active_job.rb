# lib/odsl/adapters/active_job.rb
module Odsl
  module Adapters
    class ActiveJob < Base
      def self.enqueue(service_class:, method_name:, kwargs:, key: nil, callable: nil)
        unless defined?(::ActiveJob)
          raise Odsl::Error,
            "ActiveJob is not available. Add `gem 'activejob'` to your Gemfile."
        end

        require_relative "odsl_job"
        Odsl::OdslJob.perform_later(
          service_class: service_class,
          method_name:   method_name,
          kwargs:        kwargs,
          key:           key
        )
      end
    end
  end
end

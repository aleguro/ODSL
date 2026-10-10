# lib/odsl/audit/execution_context.rb
require "active_record"
require "json"

module Odsl
  module Audit
    class ExecutionContext < ActiveRecord::Base
      self.table_name = "odsl_execution_contexts"

      has_many :step_records,
               class_name:  "Odsl::Audit::StepRecord",
               foreign_key: :execution_context_id,
               dependent:   :destroy

      STATUSES = %w[pending running completed failed].freeze

      validates :idempotency_key, presence: true, uniqueness: true
      validates :service_class,   presence: true
      validates :method_name,     presence: true
      validates :status,          inclusion: { in: STATUSES }

      scope :expired, -> { where("expires_at IS NOT NULL AND expires_at < ?", Time.now) }

      def kwargs_hash
        return {} if kwargs.nil?
        JSON.parse(kwargs).transform_keys(&:to_sym)
      end

      def completed? = status == "completed"
      def running?   = status == "running"
      def failed?    = status == "failed"
    end
  end
end

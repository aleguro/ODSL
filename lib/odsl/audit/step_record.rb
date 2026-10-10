# lib/odsl/audit/step_record.rb
require "active_record"

module Odsl
  module Audit
    class StepRecord < ActiveRecord::Base
      self.table_name = "odsl_step_records"

      belongs_to :execution_context,
                 class_name:  "Odsl::Audit::ExecutionContext",
                 foreign_key: :execution_context_id

      STATUSES = %w[pending completed failed].freeze

      validates :name,       presence: true
      validates :step_index, presence: true
      validates :status,     inclusion: { in: STATUSES }

      def completed? = status == "completed"
      def failed?    = status == "failed"

      def deserialized_result
        Audit::Serializer.load(result)
      end
    end
  end
end

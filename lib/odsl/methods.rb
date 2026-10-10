# lib/odsl/methods.rb
module Odsl
  module Methods

    def use(object)
      @delegated = instance_variable_get("@#{object}")
      self
    end

    def call(methodo)
      run_method(methodo)
      restore_delegate
      self
    end

    def to(*variables)
      variables.each_with_index do |variable, index|
        value = @last_results[index]

        if @_resuming_steps&.include?(variable.to_s)
          stored = @_execution_context
                     .step_records
                     .find_by(name: variable.to_s)
                     &.deserialized_result
          instance_variable_set("@#{variable}", stored)
        else
          instance_variable_set("@#{variable}", value)
          _record_step(variable, value)
        end
      end
      self
    end

    private

    def run_method(methodo)
      @last_results = @delegated.send(methodo, *with_attributes_resolver)
      @last_results = [@last_results] unless @last_results.is_a?(Array)
    end

    def restore_delegate
      @delegated = self
    end

    def with_attributes_resolver
      return [] if @with_attributes.nil?
      @with_attributes.map { |attribute| instance_variable_get("@#{attribute}") }
    end

    def _record_step(name, value)
      return unless @_execution_context

      @_step_index ||= 0
      serializable = Odsl::Audit::Serializer.serializable?(value)

      Odsl::Audit::StepRecord.create!(
        execution_context: @_execution_context,
        name:              name.to_s,
        step_index:        @_step_index,
        status:            "completed",
        result:            serializable ? Odsl::Audit::Serializer.dump(value) : nil,
        non_resumable:     !serializable,
        started_at:        Time.now,
        completed_at:      Time.now
      )

      @_step_index += 1
    end
  end
end

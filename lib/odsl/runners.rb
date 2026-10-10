# lib/odsl/runners.rb
require "json"

module Odsl
  module Runners
    def run(method, key: nil)
      if self.class.inmutable_mode
        _run_immutable(method, key: key)
      else
        _run_method(method, key: key)
      end
    end

    def run_in_background(method, key: nil)
      _background_adapter.enqueue(
        service_class: self.class.name,
        method_name:   method.to_s,
        kwargs:        @kwargs,
        key:           key
      )
    end

    def run_in_parallel(*methods_and_opts)
      key     = methods_and_opts.last.is_a?(Hash) ? methods_and_opts.pop[:key] : nil
      handles = methods_and_opts.map { |m| run_in_background(m, key: key) }
      handles.map { |h| h.respond_to?(:value) ? h.value : h }
    end

    private

    def _background_adapter
      case Odsl.config.background_adapter
      when :thread     then Odsl::Adapters::Thread
      when :active_job then Odsl::Adapters::ActiveJob
      else raise Odsl::Error, "Unknown background adapter: #{Odsl.config.background_adapter.inspect}"
      end
    end

    def _run_method(method, key: nil)
      ctx_result          = _setup_context(method, key)
      return nil if ctx_result == :already_completed

      @_execution_context = ctx_result
      @_current_lock      = nil
      @_step_index        = 0
      @_current_method    = method.to_s

      begin
        instance_eval(method.to_s)
        @_execution_context&.update!(status: "completed")
        _finish_result
      rescue Odsl::LockError
        raise
      rescue
        @_execution_context&.update!(status: "failed")
        raise
      ensure
        @_current_lock&.unlock rescue nil
        @_current_lock = nil
      end
    end

    def _run_immutable(method, key: nil)
      copy = dup
      copy.instance_variable_set(:@context,         @context.dup)
      copy.instance_variable_set(:@last_results,    [])
      copy.instance_variable_set(:@with_attributes, nil)
      copy.instance_variable_set(:@finish_with,     nil)
      copy.send(:_run_method, method, key: key)
    end

    def _resume_method(method, key: nil)
      @_execution_context = Odsl::Audit::ExecutionContext.find_by(idempotency_key: key)
      @_current_lock      = nil
      @_step_index        = @_execution_context.step_records.count
      @_current_method    = method.to_s

      @_execution_context.update!(status: "running")

      begin
        instance_eval(method.to_s)
        @_execution_context.update!(status: "completed")
        _finish_result
      rescue
        @_execution_context.update!(status: "failed")
        raise
      ensure
        @_current_lock&.unlock rescue nil
        @_current_lock = nil
      end
    end

    def _setup_context(method, key)
      return nil unless key && defined?(Odsl::Audit::ExecutionContext)

      ctx = Odsl::Audit::ExecutionContext.find_by(idempotency_key: key)

      if ctx
        return :already_completed if ctx.completed?
        raise Odsl::AlreadyRunningError, "Job with key '#{key}' is already running" if ctx.running?
      else
        ttl = Odsl.config.audit_ttl
        ctx = Odsl::Audit::ExecutionContext.create!(
          idempotency_key: key,
          service_class:   self.class.name,
          method_name:     method.to_s,
          kwargs:          JSON.generate(@kwargs),
          status:          "pending",
          expires_at:      ttl ? Time.now + ttl : nil
        )
      end

      ctx.update!(status: "running")
      ctx
    end

    def _finish_result
      if @finish_with.is_a?(Array)
        @finish_with.map { |variable| instance_variable_get("@#{variable}") }
      else
        instance_variable_get("@#{@finish_with}")
      end
    end
  end
end

# lib/odsl/runners.rb
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
      @_execution_context = nil
      @_current_lock      = nil
      @_step_index        = 0

      begin
        instance_eval(method.to_s)
        _finish_result
      rescue Odsl::LockError
        raise
      rescue => e
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

    def _finish_result
      if @finish_with.is_a?(Array)
        @finish_with.map { |variable| instance_variable_get("@#{variable}") }
      else
        instance_variable_get("@#{@finish_with}")
      end
    end
  end
end

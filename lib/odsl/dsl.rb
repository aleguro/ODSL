require_relative "builder"
require_relative "runners"
require_relative "methods"
require_relative "configurable"

module Odsl
  class Dsl
    include Runners
    include Methods
    extend Configurable

    def initialize(**kwargs)
      @delegated       = self
      @kwargs          = kwargs
      @context         = {}
      @last_results    = []
      @with_attributes = nil
      @finish_with     = nil

      kwargs.each do |key, value|
        instance_variable_set("@#{key}", value)
        @context[key] = value
      end
    end

    class << self
      attr_reader :inmutable_mode

      def inmutable(bool)
        @inmutable_mode = bool
      end

      def subscribe(message, to:)
        subscriptions[message] = to
      end

      def subscriptions
        @subscriptions ||= {}
      end

      def dispatch(message, **kwargs)
        method_name = subscriptions[message]
        raise Error, "No subscription for '#{message}'" unless method_name

        new(**kwargs).run(method_name)
      end

      def resume(key:)
        ctx = Odsl::Audit::ExecutionContext.find_by(idempotency_key: key)
        raise Odsl::ContextNotFoundError, "No execution context found for key: #{key}" unless ctx
        raise Odsl::AlreadyRunningError, "Job with key '#{key}' is already running" if ctx.running?
        return nil if ctx.completed?

        kwargs   = ctx.kwargs_hash
        instance = new(**kwargs)

        completed_step_names = ctx.step_records
                                  .where(status: "completed", non_resumable: false)
                                  .pluck(:name)

        instance.instance_variable_set(:@_execution_context, ctx)
        instance.instance_variable_set(:@_resuming_steps,    completed_step_names)
        instance.send(:_resume_method, ctx.method_name.to_sym, key: key)
      end
    end

    protected

    def instantiate(object, public: false)
      resolved_attrs = with_attributes_resolver

      @last_results = [] << if resolved_attrs.any?
        resolved_attrs.is_a?(Array) ? object.new(*resolved_attrs) : object.new(**resolved_attrs)
      else
        object.new
      end

      self
    end

    def build(*modules)
      @last_results = [Odsl::Builder.build(*modules).new]
      self
    end

    def with(*arguments)
      @with_attributes = arguments
      self
    end

    def value_return(*with)
      @finish_with = with
    end

    alias make        call
    alias link        call
    alias set         call
    alias get         to
    alias execute     run
    alias finish_with value_return
  end
end

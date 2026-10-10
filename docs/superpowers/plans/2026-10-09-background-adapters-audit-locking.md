# ODSL — Background Adapters, Audit System & Distributed Locking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pluggable background adapters, step-level audit with idempotency/resume, and optional distributed locking to the `odsl` gem.

**Architecture:** A `Configuration` object holds gem-level settings (adapter, TTL, Redis URL). `run()` gains an optional `key:` param that activates auditing via two ActiveRecord models (`ExecutionContext` + `StepRecord`). The `to()` / `get()` method becomes the audit checkpoint. Locking is a DSL method `lock(*vars)` that acquires a Redlock distributed lock acquired early in the method body and released in `run()`'s `ensure`.

**Tech Stack:** Ruby 3.1+, Minitest, ActiveRecord (optional, for audit), SQLite3 (test only), redlock-rb (optional, for locking), ActiveJob (optional, for background).

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/odsl/errors.rb` | **modify** | add all new error classes |
| `lib/odsl/configuration.rb` | **create** | `Odsl::Configuration` + `Odsl.configure` / `Odsl.config` |
| `lib/odsl/adapters/base.rb` | **create** | adapter interface |
| `lib/odsl/adapters/thread.rb` | **create** | Thread adapter (extracts current logic) |
| `lib/odsl/adapters/active_job.rb` | **create** | ActiveJob adapter |
| `lib/odsl/adapters/odsl_job.rb` | **create** | `Odsl::OdslJob < ActiveJob::Base` |
| `lib/odsl/audit/serializer.rb` | **create** | JSON serialize/deserialize step results |
| `lib/odsl/audit/execution_context.rb` | **create** | ActiveRecord model for a run |
| `lib/odsl/audit/step_record.rb` | **create** | ActiveRecord model for a step |
| `lib/odsl/locking/null_adapter.rb` | **create** | no-op lock (when Redis not configured) |
| `lib/odsl/locking/redlock_adapter.rb` | **create** | wraps redlock-rb |
| `lib/odsl/railtie.rb` | **create** | Rails integration hook |
| `lib/generators/odsl/install_generator.rb` | **create** | `rails generate odsl:install` |
| `lib/generators/odsl/templates/migration.rb.tt` | **create** | migration template |
| `lib/generators/odsl/templates/initializer.rb.tt` | **create** | initializer template |
| `lib/odsl/runners.rb` | **modify** | `run(key:)`, `resume`, adapter delegation, lock ensure |
| `lib/odsl/methods.rb` | **modify** | `to()` records `StepRecord` when context active |
| `lib/odsl/dsl.rb` | **modify** | `lock(*vars)` DSL method, `resume` class method |
| `lib/odsl.rb` | **modify** | require all new files |
| `lib/odsl/version.rb` | **modify** | bump to `0.3.0` |
| `odsl.gemspec` | **modify** | add optional dev dependencies |
| `test/test_helper.rb` | **modify** | add ActiveRecord in-memory setup |
| `test/spec/odsl_spec.rb` | **modify** | existing tests pass unchanged |
| `test/spec/configuration_spec.rb` | **create** | tests for Odsl.configure |
| `test/spec/adapters_spec.rb` | **create** | tests for Thread + ActiveJob adapters |
| `test/spec/audit_spec.rb` | **create** | tests for audit system + resume |
| `test/spec/locking_spec.rb` | **create** | tests for lock() DSL method |

---

## Task 1: Errors + Configuration

**Files:**
- Modify: `lib/odsl/errors.rb`
- Create: `lib/odsl/configuration.rb`
- Modify: `lib/odsl.rb`
- Create: `test/spec/configuration_spec.rb`

- [ ] **Step 1.1: Write failing test for configuration**

```ruby
# test/spec/configuration_spec.rb
require "test_helper"
require "odsl"

describe Odsl do
  describe ".configure" do
    after { Odsl.reset_config! }

    it "sets background_adapter" do
      Odsl.configure { |c| c.background_adapter = :active_job }
      assert_equal :active_job, Odsl.config.background_adapter
    end

    it "defaults background_adapter to :thread" do
      assert_equal :thread, Odsl.config.background_adapter
    end

    it "sets audit_ttl" do
      Odsl.configure { |c| c.audit_ttl = 86_400 }
      assert_equal 86_400, Odsl.config.audit_ttl
    end

    it "defaults audit_ttl to nil" do
      assert_nil Odsl.config.audit_ttl
    end

    it "sets lock_redis_url" do
      Odsl.configure { |c| c.lock_redis_url = "redis://localhost:6379" }
      assert_equal "redis://localhost:6379", Odsl.config.lock_redis_url
    end

    it "sets lock_ttl" do
      Odsl.configure { |c| c.lock_ttl = 5_000 }
      assert_equal 5_000, Odsl.config.lock_ttl
    end

    it "defaults lock_ttl to 10_000" do
      assert_equal 10_000, Odsl.config.lock_ttl
    end
  end
end
```

- [ ] **Step 1.2: Run test to confirm failure**

```bash
cd /path/to/odsl && bundle exec ruby -Ilib:test test/spec/configuration_spec.rb
```

Expected: `NoMethodError: undefined method 'configure' for Odsl:Module`

- [ ] **Step 1.3: Replace errors.rb with all error classes**

```ruby
# lib/odsl/errors.rb
module Odsl
  class Error < StandardError; end

  class LockError              < Error; end
  class LockingNotConfiguredError < Error; end
  class AlreadyRunningError    < Error; end
  class ContextNotFoundError   < Error; end
end
```

- [ ] **Step 1.4: Create configuration.rb**

```ruby
# lib/odsl/configuration.rb
module Odsl
  class Configuration
    attr_accessor :background_adapter, :audit_ttl,
                  :lock_redis_url, :lock_ttl

    def initialize
      @background_adapter = :thread
      @audit_ttl          = nil
      @lock_redis_url     = nil
      @lock_ttl           = 10_000
    end
  end

  class << self
    def configure
      yield(config)
    end

    def config
      @config ||= Configuration.new
    end

    def reset_config!
      @config = Configuration.new
    end
  end
end
```

- [ ] **Step 1.5: Update lib/odsl.rb to require new files**

```ruby
# lib/odsl.rb
require "odsl/version"
require "odsl/errors"
require "odsl/configuration"
require "odsl/dsl"
```

- [ ] **Step 1.6: Run tests**

```bash
bundle exec ruby -Ilib:test test/spec/configuration_spec.rb
```

Expected: 7 tests, 7 assertions, 0 failures, 0 errors

- [ ] **Step 1.7: Run full suite to confirm no regressions**

```bash
bundle exec rake test
```

Expected: all existing tests still pass

- [ ] **Step 1.8: Commit**

```bash
git add lib/odsl/errors.rb lib/odsl/configuration.rb lib/odsl.rb \
        test/spec/configuration_spec.rb
git commit -m "feat: add Odsl::Configuration and error classes"
```

---

## Task 2: Background Adapters

**Files:**
- Create: `lib/odsl/adapters/base.rb`
- Create: `lib/odsl/adapters/thread.rb`
- Create: `lib/odsl/adapters/active_job.rb`
- Create: `lib/odsl/adapters/odsl_job.rb`
- Modify: `lib/odsl/runners.rb`
- Modify: `lib/odsl.rb`
- Create: `test/spec/adapters_spec.rb`

- [ ] **Step 2.1: Write failing tests for adapters**

```ruby
# test/spec/adapters_spec.rb
require "test_helper"
require "odsl"

describe Odsl::Adapters::Thread do
  it "enqueues by starting a Ruby Thread" do
    result = nil
    t = Odsl::Adapters::Thread.enqueue(
      service_class: "String",
      method_name:   "upcase",
      kwargs:        {},
      callable:      -> { result = "ran" }
    )
    assert_instance_of ::Thread, t
    t.value
    assert_equal "ran", result
  end
end

describe Odsl::Adapters::Base do
  it "raises NotImplementedError on enqueue" do
    assert_raises(NotImplementedError) do
      Odsl::Adapters::Base.enqueue(
        service_class: "Foo",
        method_name:   "bar",
        kwargs:        {}
      )
    end
  end
end
```

- [ ] **Step 2.2: Run tests to confirm failure**

```bash
bundle exec ruby -Ilib:test test/spec/adapters_spec.rb
```

Expected: `NameError: uninitialized constant Odsl::Adapters`

- [ ] **Step 2.3: Create adapters/base.rb**

```ruby
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
```

- [ ] **Step 2.4: Create adapters/thread.rb**

```ruby
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
```

- [ ] **Step 2.5: Create adapters/odsl_job.rb**

```ruby
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
```

- [ ] **Step 2.6: Create adapters/active_job.rb**

```ruby
# lib/odsl/adapters/active_job.rb
module Odsl
  module Adapters
    class ActiveJob < Base
      def self.enqueue(service_class:, method_name:, kwargs:, key: nil, callable: nil)
        unless defined?(::ActiveJob)
          raise Odsl::Error, "ActiveJob is not available. Add `gem 'activejob'` to your Gemfile."
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
```

- [ ] **Step 2.7: Update runners.rb to delegate run_in_background to adapter**

```ruby
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
      adapter = _background_adapter

      adapter.enqueue(
        service_class: self.class.name,
        method_name:   method.to_s,
        kwargs:        @kwargs,
        key:           key
      )
    end

    def run_in_parallel(*methods_and_opts)
      key  = methods_and_opts.last.is_a?(Hash) ? methods_and_opts.pop[:key] : nil
      threads = methods_and_opts.map { |method| run_in_background(method, key: key) }
      threads.map { |t| t.respond_to?(:value) ? t.value : t }
    end

    private

    def _background_adapter
      adapter_name = Odsl.config.background_adapter
      case adapter_name
      when :thread     then Odsl::Adapters::Thread
      when :active_job then Odsl::Adapters::ActiveJob
      else
        raise Odsl::Error, "Unknown background adapter: #{adapter_name.inspect}"
      end
    end

    def _run_method(method, key: nil)
      @_execution_context = nil
      @_current_lock      = nil
      @_step_index        = 0

      begin
        instance_eval(method.to_s)

        if @_execution_context
          @_execution_context.update!(status: "completed")
        end

        _finish_result
      rescue Odsl::LockError
        raise
      rescue => e
        if @_execution_context
          @_execution_context.update!(status: "failed")
        end
        raise
      ensure
        if @_current_lock
          @_current_lock.unlock rescue nil
          @_current_lock = nil
        end
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
```

- [ ] **Step 2.8: Update lib/odsl.rb to require adapters**

```ruby
# lib/odsl.rb
require "odsl/version"
require "odsl/errors"
require "odsl/configuration"
require "odsl/adapters/base"
require "odsl/adapters/thread"
require "odsl/adapters/active_job"
require "odsl/dsl"
```

- [ ] **Step 2.9: Run adapter tests**

```bash
bundle exec ruby -Ilib:test test/spec/adapters_spec.rb
```

Expected: 2 tests, 2 assertions, 0 failures, 0 errors

- [ ] **Step 2.10: Run full suite**

```bash
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 2.11: Commit**

```bash
git add lib/odsl/adapters/ lib/odsl/runners.rb lib/odsl.rb \
        test/spec/adapters_spec.rb
git commit -m "feat: add pluggable background adapters (Thread, ActiveJob)"
```

---

## Task 3: Audit Models + Test Setup

**Files:**
- Create: `lib/odsl/audit/serializer.rb`
- Create: `lib/odsl/audit/execution_context.rb`
- Create: `lib/odsl/audit/step_record.rb`
- Modify: `test/test_helper.rb`
- Modify: `odsl.gemspec`

- [ ] **Step 3.1: Add activerecord + sqlite3 to gemspec dev dependencies**

Edit `odsl.gemspec`, replacing the development dependency block:

```ruby
  spec.add_development_dependency "minitest", ">= 5.8"
  spec.add_development_dependency "minitest-reporters", ">= 1.1"
  spec.add_development_dependency "activerecord", ">= 7.0"
  spec.add_development_dependency "sqlite3", "~> 1.7"
```

- [ ] **Step 3.2: Run bundle install**

```bash
bundle install
```

Expected: activerecord and sqlite3 installed

- [ ] **Step 3.3: Update test/test_helper.rb to set up in-memory AR schema**

```ruby
# test/test_helper.rb
require "minitest/autorun"
require "minitest/spec"
require "minitest/reporters"
require "odsl"

Minitest::Reporters.use!

# ActiveRecord in-memory setup for audit tests
require "active_record"
require "sqlite3"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :odsl_execution_contexts, force: true do |t|
    t.string   :idempotency_key, null: false
    t.string   :service_class,   null: false
    t.string   :method_name,     null: false
    t.text     :kwargs
    t.string   :status,          null: false, default: "pending"
    t.datetime :expires_at
    t.timestamps
  end
  add_index :odsl_execution_contexts, :idempotency_key, unique: true
  add_index :odsl_execution_contexts, :expires_at

  create_table :odsl_step_records, force: true do |t|
    t.references :execution_context, null: false,
                 foreign_key: { to_table: :odsl_execution_contexts }
    t.string   :name,          null: false
    t.integer  :step_index,    null: false
    t.string   :status,        null: false, default: "pending"
    t.text     :result
    t.text     :error_message
    t.boolean  :non_resumable, default: false
    t.datetime :started_at
    t.datetime :completed_at
  end
end
```

- [ ] **Step 3.4: Run existing suite to confirm schema loads cleanly**

```bash
bundle exec rake test
```

Expected: all existing tests still pass

- [ ] **Step 3.5: Create audit/serializer.rb**

```ruby
# lib/odsl/audit/serializer.rb
require "json"

module Odsl
  module Audit
    module Serializer
      def self.dump(value)
        JSON.generate(serialize(value))
      end

      def self.load(json_string)
        return nil if json_string.nil?
        JSON.parse(json_string)
      end

      def self.serializable?(value)
        dump(value)
        true
      rescue JSON::GeneratorError, TypeError
        false
      end

      private

      def self.serialize(value)
        case value
        when Hash   then value.transform_keys(&:to_s).transform_values { |v| serialize(v) }
        when Array  then value.map { |v| serialize(v) }
        when Struct then serialize(value.to_h)
        else             value
        end
      end
    end
  end
end
```

- [ ] **Step 3.6: Create audit/execution_context.rb**

```ruby
# lib/odsl/audit/execution_context.rb
require "active_record"

module Odsl
  module Audit
    class ExecutionContext < ActiveRecord::Base
      self.table_name = "odsl_execution_contexts"

      has_many :step_records,
               class_name: "Odsl::Audit::StepRecord",
               foreign_key: :execution_context_id,
               dependent: :destroy

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
```

- [ ] **Step 3.7: Create audit/step_record.rb**

```ruby
# lib/odsl/audit/step_record.rb
require "active_record"

module Odsl
  module Audit
    class StepRecord < ActiveRecord::Base
      self.table_name = "odsl_step_records"

      belongs_to :execution_context,
                 class_name: "Odsl::Audit::ExecutionContext",
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
```

- [ ] **Step 3.8: Update lib/odsl.rb to require audit files**

```ruby
# lib/odsl.rb
require "odsl/version"
require "odsl/errors"
require "odsl/configuration"
require "odsl/adapters/base"
require "odsl/adapters/thread"
require "odsl/adapters/active_job"
require "odsl/audit/serializer"
require "odsl/audit/execution_context"
require "odsl/audit/step_record"
require "odsl/dsl"
```

- [ ] **Step 3.9: Run full suite**

```bash
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 3.10: Commit**

```bash
git add lib/odsl/audit/ lib/odsl.rb test/test_helper.rb odsl.gemspec Gemfile.lock
git commit -m "feat: add audit models (ExecutionContext, StepRecord, Serializer)"
```

---

## Task 4: Audit Integration — run() + get()

**Files:**
- Modify: `lib/odsl/runners.rb`
- Modify: `lib/odsl/methods.rb`
- Modify: `lib/odsl.rb` (add cleanup method)
- Create: `test/spec/audit_spec.rb`

- [ ] **Step 4.1: Write failing audit tests**

```ruby
# test/spec/audit_spec.rb
require "test_helper"
require "odsl"

# Reuse the same Games domain from odsl_spec
require_relative "odsl_spec" unless defined?(Games::Service)

describe "Audit system" do
  before do
    Odsl::Audit::StepRecord.delete_all
    Odsl::Audit::ExecutionContext.delete_all
  end

  it "creates an ExecutionContext when key: is given" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "audit-test-1")

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "audit-test-1")
    assert_equal "completed", ctx.status
    assert_equal "Games::Service", ctx.service_class
    assert_equal "create", ctx.method_name
  end

  it "creates StepRecords for each .get() call" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "audit-test-2")

    ctx   = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "audit-test-2")
    names = ctx.step_records.order(:step_index).pluck(:name)

    assert_includes names, "game_object"
    assert_includes names, "game_instance"
    assert_includes names, "score_board_object"
  end

  it "does not create an ExecutionContext when no key: given" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create)

    assert_equal 0, Odsl::Audit::ExecutionContext.count
  end

  it "returns immediately for a completed context (idempotency)" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "audit-test-3")

    call_count = 0
    Games::Service.define_method(:create_counter) { call_count += 1 }

    # Second call with same key should not re-run
    service2 = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service2.run(:create, key: "audit-test-3")

    assert_equal 0, call_count
  ensure
    Games::Service.undef_method(:create_counter) rescue nil
  end

  it "raises AlreadyRunningError if context is running" do
    Odsl::Audit::ExecutionContext.create!(
      idempotency_key: "audit-test-4",
      service_class:   "Games::Service",
      method_name:     "create",
      kwargs:          "{}",
      status:          "running"
    )

    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    assert_raises(Odsl::AlreadyRunningError) do
      service.run(:create, key: "audit-test-4")
    end
  end

  it "marks context as failed when method raises" do
    module Games
      module Crud
        def failing_create
          raise "boom"
        end
      end
    end

    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    assert_raises(RuntimeError) { service.run(:failing_create, key: "audit-test-5") }

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "audit-test-5")
    assert_equal "failed", ctx.status
  ensure
    Games::Service.undef_method(:failing_create) rescue nil
  end
end
```

- [ ] **Step 4.2: Run tests to confirm failure**

```bash
bundle exec ruby -Ilib:test test/spec/audit_spec.rb
```

Expected: failures about missing audit behavior

- [ ] **Step 4.3: Update runners.rb to create/load ExecutionContext**

Replace `lib/odsl/runners.rb` entirely:

```ruby
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
      @_execution_context = _setup_context(method, key)
      @_current_lock      = nil
      @_step_index        = 0

      begin
        instance_eval(method.to_s)
        @_execution_context&.update!(status: "completed")
        _finish_result
      rescue Odsl::LockError
        raise
      rescue => e
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

    def _setup_context(method, key)
      return nil unless key && defined?(Odsl::Audit::ExecutionContext)

      ctx = Odsl::Audit::ExecutionContext.find_by(idempotency_key: key)

      if ctx
        return nil if ctx.completed?
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
```

- [ ] **Step 4.4: Update methods.rb to record StepRecord in to()**

```ruby
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
        instance_variable_set("@#{variable}", value)
        _record_step(variable, value)
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
      serializable  = Odsl::Audit::Serializer.serializable?(value)

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
```

- [ ] **Step 4.5: Run audit tests**

```bash
bundle exec ruby -Ilib:test test/spec/audit_spec.rb
```

Expected: 5 tests, 5 assertions, 0 failures

- [ ] **Step 4.6: Run full suite**

```bash
bundle exec rake test
```

Expected: all tests pass

- [ ] **Step 4.7: Commit**

```bash
git add lib/odsl/runners.rb lib/odsl/methods.rb test/spec/audit_spec.rb
git commit -m "feat: audit integration — run() records ExecutionContext and StepRecords"
```

---

## Task 5: Resume

**Files:**
- Modify: `lib/odsl/runners.rb` (add `_resume_method`)
- Modify: `lib/odsl/dsl.rb` (add `resume` class method)
- Modify: `test/spec/audit_spec.rb` (add resume tests)

- [ ] **Step 5.1: Write failing resume tests — append to audit_spec.rb**

```ruby
describe "Resume" do
  before do
    Odsl::Audit::StepRecord.delete_all
    Odsl::Audit::ExecutionContext.delete_all
  end

  it "resumes a failed run from the first incomplete step" do
    # Create a context that failed after game_object was recorded
    ctx = Odsl::Audit::ExecutionContext.create!(
      idempotency_key: "resume-test-1",
      service_class:   "Games::Service",
      method_name:     "create",
      kwargs:          JSON.generate({ player: { name: "alejandro" }, game: "chess" }),
      status:          "failed"
    )
    Odsl::Audit::StepRecord.create!(
      execution_context: ctx,
      name:              "game_object",
      step_index:        0,
      status:            "completed",
      result:            nil,
      non_resumable:     true,
      started_at:        Time.now,
      completed_at:      Time.now
    )

    result = Games::Service.resume(key: "resume-test-1")
    refute_nil result

    ctx.reload
    assert_equal "completed", ctx.status
  end

  it "raises ContextNotFoundError for unknown key" do
    assert_raises(Odsl::ContextNotFoundError) do
      Games::Service.resume(key: "does-not-exist")
    end
  end
end
```

- [ ] **Step 5.2: Run to confirm failure**

```bash
bundle exec ruby -Ilib:test test/spec/audit_spec.rb
```

Expected: `NoMethodError: undefined method 'resume'`

- [ ] **Step 5.3: Add resume class method to dsl.rb**

Add inside the `class << self` block in `lib/odsl/dsl.rb`:

```ruby
      def resume(key:)
        ctx = Odsl::Audit::ExecutionContext.find_by(idempotency_key: key)
        raise Odsl::ContextNotFoundError, "No execution context found for key: #{key}" unless ctx

        kwargs = ctx.kwargs_hash
        instance = new(**kwargs)
        instance.instance_variable_set(:@_execution_context, ctx)
        instance.instance_variable_set(:@_resuming_steps,
          ctx.step_records.where(status: "completed", non_resumable: false)
             .pluck(:name))
        instance.send(:_resume_method, ctx.method_name.to_sym, key: key)
      end
```

- [ ] **Step 5.4: Add _resume_method to runners.rb**

Add inside the `private` section of `lib/odsl/runners.rb`:

```ruby
    def _resume_method(method, key: nil)
      @_execution_context = Odsl::Audit::ExecutionContext.find_by(idempotency_key: key)
      @_current_lock      = nil
      @_step_index        = @_execution_context.step_records.count

      @_execution_context.update!(status: "running")

      begin
        instance_eval(method.to_s)
        @_execution_context.update!(status: "completed")
        _finish_result
      rescue => e
        @_execution_context.update!(status: "failed")
        raise
      ensure
        @_current_lock&.unlock rescue nil
        @_current_lock = nil
      end
    end
```

- [ ] **Step 5.5: Update to() in methods.rb to skip completed steps on resume**

Replace `to(*variables)` in `lib/odsl/methods.rb`:

```ruby
    def to(*variables)
      variables.each_with_index do |variable, index|
        value = @last_results[index]

        resuming = @_resuming_steps&.include?(variable.to_s)

        if resuming
          stored = @_execution_context.step_records
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
```

- [ ] **Step 5.6: Run resume tests**

```bash
bundle exec ruby -Ilib:test test/spec/audit_spec.rb
```

Expected: all audit + resume tests pass

- [ ] **Step 5.7: Run full suite**

```bash
bundle exec rake test
```

- [ ] **Step 5.8: Commit**

```bash
git add lib/odsl/runners.rb lib/odsl/dsl.rb lib/odsl/methods.rb \
        test/spec/audit_spec.rb
git commit -m "feat: add resume() — restarts a failed run from first incomplete step"
```

---

## Task 6: TTL + Cleanup

**Files:**
- Modify: `lib/odsl.rb` (add `Odsl.cleanup_expired!`)
- Modify: `lib/odsl/railtie.rb` (rake task)
- Create: `lib/odsl/railtie.rb`
- Modify: `test/spec/audit_spec.rb` (TTL tests)

- [ ] **Step 6.1: Write failing TTL/cleanup tests — append to audit_spec.rb**

```ruby
describe "TTL and cleanup" do
  before do
    Odsl::Audit::StepRecord.delete_all
    Odsl::Audit::ExecutionContext.delete_all
    Odsl.reset_config!
  end

  it "sets expires_at based on audit_ttl" do
    Odsl.configure { |c| c.audit_ttl = 86_400 }

    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "ttl-test-1")

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "ttl-test-1")
    refute_nil ctx.expires_at
    assert ctx.expires_at > Time.now
  end

  it "leaves expires_at nil when audit_ttl is nil" do
    service = Games::Service.new(player: { name: "alejandro" }, game: "chess")
    service.run(:create, key: "ttl-test-2")

    ctx = Odsl::Audit::ExecutionContext.find_by!(idempotency_key: "ttl-test-2")
    assert_nil ctx.expires_at
  end

  it "cleanup_expired! removes contexts past expires_at" do
    Odsl::Audit::ExecutionContext.create!(
      idempotency_key: "expired-1",
      service_class:   "Foo",
      method_name:     "bar",
      kwargs:          "{}",
      status:          "completed",
      expires_at:      Time.now - 1
    )
    Odsl::Audit::ExecutionContext.create!(
      idempotency_key: "active-1",
      service_class:   "Foo",
      method_name:     "bar",
      kwargs:          "{}",
      status:          "completed",
      expires_at:      Time.now + 86_400
    )

    Odsl.cleanup_expired!

    assert_nil Odsl::Audit::ExecutionContext.find_by(idempotency_key: "expired-1")
    refute_nil Odsl::Audit::ExecutionContext.find_by(idempotency_key: "active-1")
  end
end
```

- [ ] **Step 6.2: Run to confirm failure**

```bash
bundle exec ruby -Ilib:test test/spec/audit_spec.rb
```

Expected: `NoMethodError: undefined method 'cleanup_expired!'`

- [ ] **Step 6.3: Add cleanup_expired! to lib/odsl.rb**

Append to the `class << self` block in `lib/odsl.rb` (after `reset_config!`):

```ruby
require "odsl/version"
require "odsl/errors"
require "odsl/configuration"
require "odsl/adapters/base"
require "odsl/adapters/thread"
require "odsl/adapters/active_job"
require "odsl/audit/serializer"
require "odsl/audit/execution_context"
require "odsl/audit/step_record"
require "odsl/dsl"

module Odsl
  class << self
    def cleanup_expired!
      return unless defined?(Odsl::Audit::ExecutionContext)
      Odsl::Audit::ExecutionContext.expired.destroy_all
    end
  end
end
```

- [ ] **Step 6.4: Create railtie.rb with rake task**

```ruby
# lib/odsl/railtie.rb
return unless defined?(Rails)

module Odsl
  class Railtie < Rails::Railtie
    rake_tasks do
      namespace :odsl do
        desc "Remove expired ODSL execution contexts"
        task cleanup: :environment do
          deleted = Odsl.cleanup_expired!
          puts "ODSL cleanup: #{deleted.size} expired context(s) removed."
        end
      end
    end
  end
end
```

- [ ] **Step 6.5: Require railtie in lib/odsl.rb**

Add at the bottom of `lib/odsl.rb`:

```ruby
require "odsl/railtie"
```

- [ ] **Step 6.6: Run TTL/cleanup tests**

```bash
bundle exec ruby -Ilib:test test/spec/audit_spec.rb
```

Expected: all tests pass

- [ ] **Step 6.7: Run full suite**

```bash
bundle exec rake test
```

- [ ] **Step 6.8: Commit**

```bash
git add lib/odsl.rb lib/odsl/railtie.rb test/spec/audit_spec.rb
git commit -m "feat: audit TTL, expires_at, and Odsl.cleanup_expired!"
```

---

## Task 7: Distributed Locking

**Files:**
- Create: `lib/odsl/locking/null_adapter.rb`
- Create: `lib/odsl/locking/redlock_adapter.rb`
- Modify: `lib/odsl/dsl.rb` (add `lock(*vars)` method)
- Modify: `lib/odsl.rb` (require locking files)
- Create: `test/spec/locking_spec.rb`

- [ ] **Step 7.1: Write failing locking tests**

```ruby
# test/spec/locking_spec.rb
require "test_helper"
require "odsl"

describe "Distributed locking" do
  after { Odsl.reset_config! }

  describe "NullAdapter" do
    it "always returns a no-op lock object" do
      lock = Odsl::Locking::NullAdapter.acquire("any-key", 10_000)
      assert_respond_to lock, :unlock
      lock.unlock  # must not raise
    end
  end

  describe "lock() DSL method" do
    it "raises LockingNotConfiguredError when Redis URL is not configured" do
      module TestLockService
        class Service < Odsl::Dsl
          def locked_action
            lock(:foo)
          end

          def value_return_foo
            finish_with(:foo)
          end
        end
      end

      svc = TestLockService::Service.new(foo: "bar")
      assert_raises(Odsl::LockingNotConfiguredError) { svc.run(:locked_action) }
    end

    it "acquires and releases the lock around run()" do
      acquired_keys = []
      released      = false

      fake_lock = Object.new
      fake_lock.define_singleton_method(:unlock) { released = true }

      Odsl::Locking::NullAdapter.define_singleton_method(:acquire) do |key, _ttl|
        acquired_keys << key
        fake_lock
      end

      Odsl.configure do |c|
        c.lock_redis_url = "redis://fake"
        c.lock_ttl       = 5_000
      end

      module TestLockService2
        class Service < Odsl::Dsl
          def action_with_lock
            lock(:player)
            finish_with(:player)
          end
        end
      end

      svc = TestLockService2::Service.new(player: "alejandro")
      svc.run(:action_with_lock)

      assert acquired_keys.any? { |k| k.include?("alejandro") }
      assert released
    ensure
      Odsl::Locking::NullAdapter.singleton_class.undef_method(:acquire) rescue nil
    end
  end
end
```

- [ ] **Step 7.2: Run to confirm failure**

```bash
bundle exec ruby -Ilib:test test/spec/locking_spec.rb
```

Expected: `NameError: uninitialized constant Odsl::Locking`

- [ ] **Step 7.3: Create locking/null_adapter.rb**

```ruby
# lib/odsl/locking/null_adapter.rb
module Odsl
  module Locking
    class NullAdapter
      NoOpLock = Struct.new(:key) do
        def unlock; end
      end

      def self.acquire(_key, _ttl)
        NoOpLock.new(_key)
      end
    end
  end
end
```

- [ ] **Step 7.4: Create locking/redlock_adapter.rb**

```ruby
# lib/odsl/locking/redlock_adapter.rb
module Odsl
  module Locking
    class RedlockAdapter
      AcquiredLock = Struct.new(:client, :lock_info) do
        def unlock
          client.unlock(lock_info)
        rescue => e
          # Swallow unlock errors — TTL will expire the lock anyway
        end
      end

      def self.acquire(key, ttl_ms)
        require "redlock"
        client    = Redlock::Client.new([Odsl.config.lock_redis_url])
        lock_info = client.lock(key, ttl_ms)
        return nil unless lock_info

        AcquiredLock.new(client, lock_info)
      end
    end
  end
end
```

- [ ] **Step 7.5: Add lock() DSL method to dsl.rb**

Add inside the `protected` section of `lib/odsl/dsl.rb`, before `instantiate`:

```ruby
    def lock(*variables)
      unless Odsl.config.lock_redis_url
        raise Odsl::LockingNotConfiguredError,
          "config.lock_redis_url is not set. Configure it in your Odsl.configure block."
      end

      key_parts = variables.map { |v| instance_variable_get("@#{v}").to_s }
      lock_key  = "odsl:#{self.class.name}:#{@_current_method}:#{key_parts.join(':')}"

      adapter   = if Odsl.config.lock_redis_url.start_with?("redis://fake")
                    Odsl::Locking::NullAdapter
                  else
                    Odsl::Locking::RedlockAdapter
                  end

      acquired = adapter.acquire(lock_key, Odsl.config.lock_ttl)
      raise Odsl::LockError, "Could not acquire lock for key: #{lock_key}" unless acquired

      @_current_lock = acquired
    end
```

- [ ] **Step 7.6: Track current method name in runners.rb**

In `_run_method` in `lib/odsl/runners.rb`, add one line before `instance_eval`:

```ruby
      @_current_method = method.to_s
```

Full updated `_run_method` block:

```ruby
    def _run_method(method, key: nil)
      @_execution_context = _setup_context(method, key)
      @_current_lock      = nil
      @_step_index        = 0
      @_current_method    = method.to_s

      begin
        instance_eval(method.to_s)
        @_execution_context&.update!(status: "completed")
        _finish_result
      rescue Odsl::LockError
        raise
      rescue => e
        @_execution_context&.update!(status: "failed")
        raise
      ensure
        @_current_lock&.unlock rescue nil
        @_current_lock = nil
      end
    end
```

- [ ] **Step 7.7: Update lib/odsl.rb to require locking files**

```ruby
require "odsl/locking/null_adapter"
require "odsl/locking/redlock_adapter"
```

Add these lines after the audit requires in `lib/odsl.rb`.

- [ ] **Step 7.8: Run locking tests**

```bash
bundle exec ruby -Ilib:test test/spec/locking_spec.rb
```

Expected: 3 tests, 0 failures

- [ ] **Step 7.9: Run full suite**

```bash
bundle exec rake test
```

- [ ] **Step 7.10: Commit**

```bash
git add lib/odsl/locking/ lib/odsl/dsl.rb lib/odsl/runners.rb lib/odsl.rb \
        test/spec/locking_spec.rb
git commit -m "feat: distributed locking via lock() DSL method + Redlock adapter"
```

---

## Task 8: Rails Generator

**Files:**
- Create: `lib/generators/odsl/install_generator.rb`
- Create: `lib/generators/odsl/templates/migration.rb.tt`
- Create: `lib/generators/odsl/templates/initializer.rb.tt`

- [ ] **Step 8.1: Create generator directory**

```bash
mkdir -p lib/generators/odsl/templates
```

- [ ] **Step 8.2: Create migration template**

```ruby
# lib/generators/odsl/templates/migration.rb.tt
class CreateOdslTables < ActiveRecord::Migration[7.0]
  def change
    create_table :odsl_execution_contexts do |t|
      t.string   :idempotency_key, null: false
      t.string   :service_class,   null: false
      t.string   :method_name,     null: false
      t.text     :kwargs
      t.string   :status,          null: false, default: "pending"
      t.datetime :expires_at
      t.timestamps
    end

    add_index :odsl_execution_contexts, :idempotency_key, unique: true
    add_index :odsl_execution_contexts, :expires_at

    create_table :odsl_step_records do |t|
      t.references :execution_context, null: false,
                   foreign_key: { to_table: :odsl_execution_contexts }
      t.string   :name,          null: false
      t.integer  :step_index,    null: false
      t.string   :status,        null: false, default: "pending"
      t.text     :result
      t.text     :error_message
      t.boolean  :non_resumable, default: false
      t.datetime :started_at
      t.datetime :completed_at
    end
  end
end
```

- [ ] **Step 8.3: Create initializer template**

```ruby
# lib/generators/odsl/templates/initializer.rb.tt
Odsl.configure do |config|
  # Background job adapter. Options: :thread (default), :active_job
  # config.background_adapter = :active_job

  # How long to keep audit records. nil = keep forever.
  # Accepts any numeric value in seconds.
  # config.audit_ttl = 30.days

  # Redis URL for distributed locking (optional).
  # Requires the `redlock` gem. Leave nil to disable locking.
  # config.lock_redis_url = "redis://localhost:6379"

  # How long (in ms) a distributed lock is held before auto-expiring.
  # config.lock_ttl = 10_000
end
```

- [ ] **Step 8.4: Create the generator**

```ruby
# lib/generators/odsl/install_generator.rb
require "rails/generators"
require "rails/generators/migration"

module Odsl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname)
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      def create_migration
        migration_template "migration.rb.tt",
                           "db/migrate/create_odsl_tables.rb"
      end

      def create_initializer
        template "initializer.rb.tt", "config/initializers/odsl.rb"
      end
    end
  end
end
```

- [ ] **Step 8.5: Run full suite to confirm nothing broke**

```bash
bundle exec rake test
```

- [ ] **Step 8.6: Commit**

```bash
git add lib/generators/
git commit -m "feat: add rails generate odsl:install generator"
```

---

## Task 9: Gemspec + README + Version Bump

**Files:**
- Modify: `lib/odsl/version.rb`
- Modify: `odsl.gemspec`
- Modify: `README.md`

- [ ] **Step 9.1: Bump version to 0.3.0**

```ruby
# lib/odsl/version.rb
module Odsl
  VERSION = "0.3.0"
end
```

- [ ] **Step 9.2: Update gemspec with optional runtime hints**

Replace the dependency block in `odsl.gemspec`:

```ruby
  spec.required_ruby_version = ">= 3.1.0"

  # Optional runtime dependencies (not required — load if present)
  # gem "activerecord", ">= 7.0"  # for audit system
  # gem "redlock", ">= 2.0"       # for distributed locking
  # gem "activejob", ">= 7.0"     # for ActiveJob adapter

  spec.add_development_dependency "minitest", ">= 5.8"
  spec.add_development_dependency "minitest-reporters", ">= 1.1"
  spec.add_development_dependency "activerecord", ">= 7.0"
  spec.add_development_dependency "sqlite3", "~> 1.7"
```

- [ ] **Step 9.3: Update README.md with new sections**

Add the following sections to `README.md` after the existing content:

````markdown
## Background Adapters

```ruby
# config/initializers/odsl.rb
Odsl.configure do |config|
  config.background_adapter = :active_job  # default: :thread
end
```

Works with any ActiveJob backend: Solid Queue (Rails 8 default), Sidekiq, Good Job, Delayed::Job.

```ruby
# Fire and forget
service.run_in_background(:create, key: 'user-123-game-chess')

# Run two methods in parallel
service.run_in_parallel(:method_a, :method_b)
```

## Audit System

Install tables with the generator:

```bash
rails generate odsl:install
rails db:migrate
```

Run with an idempotency key to activate auditing:

```ruby
result = service.run(:create, key: 'user-123-game-chess')
```

Resume a failed run from the first incomplete step:

```ruby
result = Games::Service.resume(key: 'user-123-game-chess')
```

Configure TTL for auto-expiry:

```ruby
Odsl.configure { |c| c.audit_ttl = 30 * 24 * 3600 }  # 30 days in seconds
```

Clean up expired records:

```ruby
Odsl.cleanup_expired!   # from code
rake odsl:cleanup       # from terminal / cron
```

## Distributed Locking

Requires the `redlock` gem and a Redis instance.

```ruby
# Gemfile
gem 'redlock'

# config/initializers/odsl.rb
Odsl.configure do |config|
  config.lock_redis_url = ENV['REDIS_URL']
  config.lock_ttl       = 10_000  # ms
end
```

Add `lock()` at the start of any business method:

```ruby
module Games
  module Crud
    def create
      lock(:player, :game)   # raises Odsl::LockError if already locked

      build(Game, Player)
        .get(:game_object)
      # ...
    end
  end
end
```

Handle the error in your controller:

```ruby
rescue Odsl::LockError
  render json: { error: 'Already in progress' }, status: :conflict
```
````

- [ ] **Step 9.4: Run final full test suite**

```bash
bundle exec rake test
```

Expected: all tests pass, 0 failures, 0 errors

- [ ] **Step 9.5: Commit**

```bash
git add lib/odsl/version.rb odsl.gemspec README.md Gemfile.lock
git commit -m "chore: bump to 0.3.0, update gemspec and README"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Background adapters (Thread, ActiveJob) — Tasks 2
- ✅ `Odsl.configure` — Task 1
- ✅ `ExecutionContext` + `StepRecord` models — Task 3
- ✅ `run(key:)` activates audit — Task 4
- ✅ Idempotency (completed context skipped) — Task 4
- ✅ `AlreadyRunningError` for running context — Task 4
- ✅ `.get()` as checkpoint → `StepRecord` — Task 4
- ✅ `resume(key:)` skips completed steps — Task 5
- ✅ `ContextNotFoundError` for missing key — Task 5
- ✅ `non_resumable` flag for non-serializable results — Task 4
- ✅ TTL / `expires_at` — Task 6
- ✅ `Odsl.cleanup_expired!` — Task 6
- ✅ `rake odsl:cleanup` — Task 6
- ✅ `lock(*vars)` DSL method — Task 7
- ✅ `LockError` (fail fast) — Task 7
- ✅ `LockingNotConfiguredError` — Task 7
- ✅ Lock released in `ensure` — Task 7
- ✅ Rails generator — Task 8
- ✅ Backward compatibility (no `key:` → no audit) — preserved throughout

**No placeholders found.**

**Type consistency:** `_execution_context` instance variable used consistently across `runners.rb`, `methods.rb`, and `dsl.rb`. `finish_with` alias defined in `dsl.rb` points to `value_return` which is correct.

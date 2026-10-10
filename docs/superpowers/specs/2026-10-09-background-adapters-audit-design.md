# ODSL — Background Adapters, Audit System & Distributed Locking

**Date:** 2026-10-09  
**Author:** alejandro gurovich  
**Status:** Approved

---

## Overview

This document describes three interconnected features for the `odsl` gem:

1. **Background adapters** — pluggable backends for `run_in_background` (Thread, ActiveJob)
2. **Audit system** — step-level execution tracking with idempotency and resume
3. **Distributed locking** — optional Redlock integration to prevent concurrent duplicate runs

The gem targets **Ruby on Rails applications**. All features are opt-in and backward-compatible: existing code with no `key:` or `lock` call behaves exactly as before.

---

## 1. Background Adapters

### Architecture

```
lib/odsl/adapters/
  base.rb        ← common interface
  thread.rb      ← default (plain Ruby Thread)
  active_job.rb  ← Rails bridge (Sidekiq, Solid Queue, Good Job, etc.)
```

### Interface (base.rb)

```ruby
module Odsl
  module Adapters
    class Base
      def self.enqueue(service_class:, method_name:, kwargs:, key: nil)
        raise NotImplementedError
      end
    end
  end
end
```

### Thread adapter

Current implementation. Returns a `Thread`; caller can block on `.value` to get the result. Used as the default when no adapter is configured.

### ActiveJob adapter

Defines `Odsl::OdslJob < ActiveJob::Base` (lives in `lib/odsl/adapters/odsl_job.rb`) that receives `service_class`, `method_name`, `kwargs`, and `key`. Compatible with any ActiveJob backend: Solid Queue, Sidekiq, Good Job, Delayed::Job, Resque.

Returns the enqueued job object (has `.job_id`).

### Configuration

```ruby
# config/initializers/odsl.rb
Odsl.configure do |config|
  config.background_adapter = :active_job  # default: :thread
end
```

---

## 2. Audit System

### Design decision: checkpoints at `.get()`

`.get(:variable)` is already the natural checkpoint of the DSL — it names and stores a step result. The audit system hooks into `.get()` to record a `StepRecord` after each call, making it the single source of truth for step identity.

### Database tables

**`odsl_execution_contexts`**

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `idempotency_key` | string | unique index |
| `service_class` | string | e.g. `"Games::Service"` |
| `method_name` | string | e.g. `"create"` |
| `kwargs` | jsonb/text | initial kwargs, JSON serialized |
| `status` | string | `pending / running / completed / failed` |
| `expires_at` | datetime | indexed; nil = never expires |
| `created_at` | datetime | |
| `updated_at` | datetime | |

**`odsl_step_records`**

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `execution_context_id` | bigint FK | indexed |
| `name` | string | variable name from `.get(:x)` |
| `step_index` | integer | execution order |
| `status` | string | `completed / failed` |
| `result` | jsonb/text | serialized result |
| `error_message` | text | populated on failure |
| `non_resumable` | boolean | true if result couldn't be serialized |
| `started_at` | datetime | |
| `completed_at` | datetime | |

### Public API

```ruby
# Run with audit
service.run(:create, key: 'user-123-game-chess')

# Resume from first failed/pending step
Games::Service.resume(key: 'user-123-game-chess')

# Background with audit + idempotency
service.run_in_background(:create, key: 'user-123-game-chess')
```

### Run flow (with key)

1. `run(:method, key:)` finds or creates an `ExecutionContext` for the key.
2. If the context is already `completed`, returns the stored result immediately (idempotency).
3. If `running`, raises `Odsl::AlreadyRunningError`.
4. Sets context status to `running`.
5. Executes the method. On each `.get(:x)` call, records a `StepRecord` with the serialized result.
6. On success: sets context status to `completed`.
7. On failure: sets context and the failing step to `failed` with the error message.

### Resume flow

1. Load `ExecutionContext` by key; raise `Odsl::ContextNotFoundError` if missing.
2. Collect names of already-`completed` steps.
3. Instantiate the service with the original `kwargs`.
4. Re-execute the method. When `.get(:x)` is called:
   - If `x` is in the completed set → load result from `StepRecord`, skip re-execution of the preceding step.
   - Otherwise → execute normally and record.
5. Continue until method finishes or a new failure occurs.

### Serialization contract

Results stored via `.get(:x)` must be JSON-serializable for resume to work (hashes, arrays, strings, numbers, structs with `to_h`). If a result cannot be serialized, the step is marked `completed` in the audit but flagged as `non_resumable: true`. On resume, non-resumable steps are re-executed (safe because idempotency lives in the business logic).

### TTL and cleanup

```ruby
Odsl.configure do |config|
  config.audit_ttl = 30.days  # nil = keep forever
end

# Purge expired contexts (cascade deletes step_records)
Odsl.cleanup_expired!

# Via rake
rake odsl:cleanup
```

`expires_at` is set on context creation from `config.audit_ttl`. Cleanup can be scheduled via Solid Queue scheduler, Sidekiq-Cron, Good Job cron, or a plain cron job — the gem only provides the method.

---

## 3. Distributed Locking (Redlock)

### Motivation

Idempotency handles *"already completed — skip"*. Redlock handles *"currently running in another process — block"*. Without it, two simultaneous requests with the same key can both pass the idempotency check before either has written to the DB.

### Optional dependency

Redlock requires Redis. If `config.lock_redis_url` is nil (default), calling `.lock()` in a service raises `Odsl::LockingNotConfiguredError` at boot time.

### DSL method

```ruby
def create
  lock(:player, :game)   # compose lock key from variable values

  build(Game, Player)
    .get(:game_object)
  # ...
end
```

The lock key is composed as:
```
odsl:{ServiceClass}:{method}:{var1_value}:{var2_value}
```

Example: `odsl:Games::Service:create:alejandro:chess`

### Behavior

- Lock is acquired at the start of `run` if `.lock()` is called in the method.
- If the lock cannot be acquired → raises `Odsl::LockError` immediately (fail fast).
- Lock is released when `run` finishes (success or error).
- A TTL fallback ensures the lock is released even if the process dies.

### Configuration

```ruby
Odsl.configure do |config|
  config.lock_redis_url = 'redis://localhost:6379'  # nil = disabled
  config.lock_ttl       = 10_000                    # milliseconds, fallback TTL
end
```

### Error handling

```ruby
rescue Odsl::LockError
  render json: { error: 'This action is already in progress.' }, status: :conflict

rescue Odsl::AlreadyRunningError
  # Raised when run() is called with a key that is currently status: running

rescue Odsl::ContextNotFoundError
  # Raised when resume() is called with a key that doesn't exist in the DB

rescue Odsl::LockingNotConfiguredError
  # Raised at boot if .lock() is used but no Redis URL is configured
```

---

## 4. Generator

```bash
rails generate odsl:install
```

Generates:
- `db/migrate/TIMESTAMP_create_odsl_tables.rb` — creates both tables with correct indexes
- `config/initializers/odsl.rb` — configuration template with all options commented

---

## 5. New files summary

```
lib/odsl/
  adapters/
    base.rb
    thread.rb
    active_job.rb
    odsl_job.rb        ← ActiveJob::Base subclass used by active_job adapter
  audit/
    execution_context.rb   ← ActiveRecord model
    step_record.rb         ← ActiveRecord model
    serializer.rb          ← JSON serialize/deserialize
  locking/
    redlock_adapter.rb     ← wraps redlock-rb gem
    null_adapter.rb        ← no-op when locking not configured
  configuration.rb         ← Odsl::Configuration + Odsl.configure
  railtie.rb               ← Rails integration (generator, rake tasks)
lib/generators/
  odsl/
    install_generator.rb
    templates/
      migration.rb.tt
      initializer.rb.tt
```

---

## 6. Backward compatibility

- `run(:method)` with no `key:` — no audit, no locking, behaves exactly as today.
- `run_in_background(:method)` with no `key:` — uses Thread adapter unless `background_adapter` is configured.
- `.lock()` without Redis configured — raises `Odsl::LockingNotConfiguredError` at boot.
- No new required dependencies — `redlock` and `activerecord` are optional; the gem works standalone.

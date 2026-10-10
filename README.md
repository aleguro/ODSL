# Odsl

[![Gem Version](https://badge.fury.io/rb/odsl.svg)](https://badge.fury.io/rb/odsl)
[![CI](https://github.com/aleguro/ODSL/actions/workflows/ci.yml/badge.svg)](https://github.com/aleguro/ODSL/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.txt)
[![Maintainability](https://img.shields.io/badge/maintainability-A-brightgreen)](https://github.com/aleguro/ODSL)
[![RubyGems MFA](https://img.shields.io/badge/rubygems%20MFA-enabled-green)](https://guides.rubygems.org/mfa-requirement-opt-in/)

> **O**bject **D**SL — a fluent, chainable framework for writing service objects in Ruby that are easy to read, test, and extend.

Odsl lets you express complex business workflows as a sequence of named steps — composing objects, calling methods, and storing intermediate results — without the sprawling `def call` anti-pattern. Every service is immutable by default, background-capable, audit-ready, and optionally protected by distributed locking.

---

## Why Odsl?

Most Ruby service objects end up as a `call` method with a hundred lines of code, private helpers tangled with side effects, and zero insight into which step failed when something goes wrong.

Odsl solves this by making each step **named**, **recorded**, and **resumable**:

```ruby
def create_order
  build(Inventory, Pricing)       # compose a scoped object
    .get(:catalog)                 # store it as @catalog

  with(:catalog, :items, :user)
    .make(:calculate_total)        # call your private method
    .get(:order_total)             # store the result

  with(:user, :order_total)
    .instantiate(Order)            # build an AR model
    .get(:order)

  with(:order)
    .make(:charge_customer)
    .get(:payment)

  finish_with(:order, :payment)    # declare what to return
end
```

Each `.get(:var)` is a named checkpoint — recorded to the audit log, replayable on resume, and crystal clear in stack traces.

---

## Installation

```ruby
# Gemfile
gem "odsl"

# Optional: background jobs
gem "activejob"

# Optional: distributed locking
gem "redlock"
```

For audit tables (Rails):

```bash
rails generate odsl:install
rails db:migrate
```

---

## Quick Start

```ruby
# Define your modules (plain Ruby — no inheritance required)
module Player
  attr_reader :player

  def with_player(player)
    @player = Struct.new(:name).new(player)
    self
  end
end

module Game
  attr_reader :game

  def start(game_type)
    @game = Struct.new(:game_type, :player).new(game_type, @player.name)
    self
  end
end

# Define your service
class GameService < Odsl::Dsl
  include GameCrud
  inmutable true

  subscribe 'start_game', to: :create
end

module GameCrud
  def create
    build(Game, Player)
      .get(:game_object)

    with(:player, :game, :game_object)
      .make(:new_game)
      .get(:game_instance)

    with(:game_instance)
      .instantiate(ScoreBoard)
      .get(:score_board)

    finish_with(:game_instance, :score_board)
  end

  private

  def new_game(player, game, game_object)
    game_object
      .with_player(player[:name])
      .start(game)
  end
end

# Run it
game, board = GameService.new(player: { name: "alejandro" }, game: "chess").run(:create)
game.game.game_type   # => "chess"
game.game.player      # => "alejandro"

# Or via event dispatch
game, board = GameService.dispatch('start_game', player: { name: "alejandro" }, game: "chess")
```

---

## DSL Reference

### Chaining Methods

| Method | Alias(es) | Description |
|--------|-----------|-------------|
| `build(*modules)` | — | Composes a new object by mixing modules into an anonymous class |
| `with(*attrs)` | — | Sets the arguments passed to the next `make`/`call`/`instantiate` |
| `make(:method)` | `set`, `link` | Calls a private method with the current `with` attrs |
| `call(:method)` | — | Calls a method on the currently delegated object |
| `get(*vars)` | `to` | Stores last result(s) into named instance variables |
| `use(:object)` | — | Points delegation to the object in `@object` |
| `instantiate(Class)` | — | Instantiates a class using the current `with` attrs |
| `finish_with(*vars)` | `value_return` | Declares the return value(s) of `run` |

### Running

| Method | Description |
|--------|-------------|
| `instance.run(:method)` | Executes a method, returns `finish_with` values |
| `instance.execute(:method)` | Alias for `run` |
| `MyService.resume(key:)` | Resumes a failed run from the first incomplete step |

### Class-Level DSL

| Method | Description |
|--------|-------------|
| `inmutable true` | Each `run` operates on a fresh dup — no shared state |
| `subscribe 'event', to: :method` | Maps a string event name to a method |
| `dispatch('event', **kwargs)` | Finds the subscription and runs it |

---

## Features

### Immutability

```ruby
class ReportService < Odsl::Dsl
  inmutable true
end

service = ReportService.new(year: 2024)
result1 = service.run(:generate)
result2 = service.run(:generate)  # identical — original service is untouched
```

When `inmutable true` is set, every `run` works on a `dup` of the instance — your kwargs and context are never mutated.

---

### Background Jobs

```ruby
# Fire and forget (returns a Thread by default)
thread = service.run_in_background(:process)
result = thread.value  # wait for it

# Run multiple steps in parallel
game1, game2 = service.run_in_parallel(:create, :create)
```

Switch adapters as your stack grows:

```ruby
Odsl.configure do |config|
  config.background_adapter = :active_job  # delegates to your configured queue backend
end
```

With `:active_job`, Odsl enqueues an `Odsl::OdslJob` that reconstructs the service from its kwargs and calls the method. Works with Sidekiq, Solid Queue, Good Job, and any other ActiveJob backend.

---

### Audit & Idempotency

Every `run` can be made idempotent by passing a `key:`. Odsl records an `ExecutionContext` and a `StepRecord` per `.get(:var)` checkpoint.

```ruby
# Won't re-run if already completed with this key
service.run(:process_order, key: "order-#{order.id}")

# A second call with the same key returns nil immediately
service.run(:process_order, key: "order-#{order.id}")  # => nil
```

**Step-level audit** means you can see exactly which steps completed and what their results were:

```ruby
ctx = Odsl::Audit::ExecutionContext.find_by(idempotency_key: "order-42")
ctx.status          # => "completed"
ctx.step_records    # => [#<StepRecord name="catalog">, #<StepRecord name="order_total">, ...]
```

**Resume a failed run** from the first step that wasn't recorded:

```ruby
# Process died after step 2 of 5 — resume picks up from step 3
result = OrderService.resume(key: "order-42")
```

Completed steps are loaded from the database (no side effects re-run). Non-serializable results (complex objects) are re-executed.

**TTL & cleanup:**

```ruby
Odsl.configure do |config|
  config.audit_ttl = 7 * 24 * 3600  # expire records after 1 week
end

# Remove expired records
Odsl.cleanup_expired!

# Or with Rake
rake odsl:cleanup
```

**Rails setup:**

```bash
rails generate odsl:install
rails db:migrate
```

Generates `config/initializers/odsl.rb` and a migration for `odsl_execution_contexts` + `odsl_step_records`.

---

### Distributed Locking

Prevent double-execution when users submit the same action from two browser tabs simultaneously.

```ruby
# Gemfile
gem "redlock"
```

```ruby
Odsl.configure do |config|
  config.lock_redis_url = ENV["REDIS_URL"]
  config.lock_ttl       = 10_000  # ms — how long to hold the lock
end
```

Call `lock` at the top of any business method:

```ruby
def process_order
  lock(:order_id)  # key = "OrderService:42"

  with(:order_id)
    .make(:fetch_order)
    .get(:order)

  # ...
  finish_with(:order)
end
```

`lock` builds the key from the service class name + the string values of the given instance variables. If the lock is already held, `Odsl::LockError` is raised immediately (fail-fast — no waiting). The lock is released automatically in the `ensure` block.

`lock` is a **no-op** when `lock_redis_url` is not configured, so the same code works in development without Redis.

---

### Event Bus

```ruby
class GameService < Odsl::Dsl
  include Crud

  subscribe 'game.start',  to: :create
  subscribe 'game.finish', to: :end_game
end

# Dispatch by event name
result = GameService.dispatch('game.start', player: { name: 'alejandro' }, game: 'chess')
```

Useful for decoupling event producers from the service implementation — the event string is the contract, not the method name.

---

## Configuration Reference

```ruby
Odsl.configure do |config|
  # :thread (default) or :active_job
  config.background_adapter = :thread

  # Seconds to keep audit records. nil = never expire.
  config.audit_ttl = nil

  # Redis URL for Redlock. nil = locking disabled (no-op).
  config.lock_redis_url = nil

  # Distributed lock TTL in milliseconds.
  config.lock_ttl = 10_000
end
```

---

## Error Reference

| Error | When raised |
|-------|-------------|
| `Odsl::LockError` | Distributed lock couldn't be acquired |
| `Odsl::AlreadyRunningError` | Idempotency key is currently in a `running` state |
| `Odsl::ContextNotFoundError` | `resume(key:)` called for an unknown key |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions, code style, and the PR checklist.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full history of releases.

---

## License

MIT — see [LICENSE.txt](LICENSE.txt).

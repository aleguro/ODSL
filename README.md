# Odsl

A DSL framework for building service objects in Ruby — decoupling business logic from implementation details, with built-in support for immutability, background jobs, audit/idempotency, and distributed locking.

## Installation

Add to your Gemfile:

```ruby
gem "odsl"
```

Then run:

```bash
bundle install
```

## Quick Start

```ruby
class UserService < Odsl::Dsl
  include UserCrud

  inmutable true
end

module UserCrud
  def create
    build(User, Validator)
      .get(:user_object)

    with(:user_object, :email)
      .make(:new_user)
      .get(:user)

    finish_with(:user)
  end

  private

  def new_user(user_object, email)
    user_object.create!(email: email)
  end
end

result = UserService.new(email: "user@example.com").run(:create)
```

## DSL Reference

### Core

| Method | Alias(es) | Description |
|--------|-----------|-------------|
| `build(*modules)` | — | Dynamically composes a class from modules |
| `with(*args)` | — | Sets arguments for the next method call |
| `make(:method)` | `set`, `link` | Calls a private method with the current `with` arguments |
| `call(:method)` | — | Calls a method on a delegated object |
| `get(:var)` | `to` | Stores last results into named instance variables |
| `use(:object)` | — | Delegates the next call to the object stored in `var` |
| `instantiate(Class)` | — | Instantiates a class with the current `with` arguments |
| `finish_with(*vars)` | `value_return` | Declares what to return from `run` |
| `run(:method)` | `execute` | Executes a method and returns the `finish_with` values |

### Configuration

| Method | Description |
|--------|-------------|
| `inmutable true` | Makes runs side-effect free (each run works on a dup) |
| `subscribe 'event', to: :method` | Subscribes to a named message |
| `dispatch('event', **kwargs)` | Dispatches a message by name |

### Background Jobs

```ruby
# Run in background (returns Thread or ActiveJob handle)
thread = service.run_in_background(:create)
result = thread.value

# Run multiple in parallel — returns array of results
results = service.run_in_parallel(:create, :update)
```

Configure the adapter:

```ruby
Odsl.configure do |config|
  config.background_adapter = :active_job  # or :thread (default)
end
```

### Audit & Idempotency

Requires Rails and the install generator:

```bash
rails generate odsl:install
rails db:migrate
```

```ruby
# Idempotent run — won't re-run if already completed
service.run(:create, key: "order-#{order_id}")

# Resume a failed run from the first incomplete step
UserService.resume(key: "order-#{order_id}")
```

Configure TTL:

```ruby
Odsl.configure do |config|
  config.audit_ttl = 7 * 24 * 3600  # 1 week (in seconds)
end
```

Cleanup expired records:

```ruby
Odsl.cleanup_expired!
# or via rake:
# rake odsl:cleanup
```

### Distributed Locking

Requires the `redlock` gem and a Redis server:

```ruby
gem "redlock"
```

```ruby
Odsl.configure do |config|
  config.lock_redis_url = ENV["REDIS_URL"]
  config.lock_ttl       = 10_000  # ms
end
```

Call `lock` at the start of a business method:

```ruby
def create
  lock(:user_id)  # acquires lock based on class name + @user_id value

  build(User).get(:user_object)
  # ...
end
```

Raises `Odsl::LockError` if the lock cannot be acquired (fail-fast).

## Event Subscriptions

```ruby
class Service < Odsl::Dsl
  include Crud

  inmutable true

  subscribe 'start_game', to: :create
  subscribe 'end_game',   to: :delete
end

# Dispatch by message name
result = Service.dispatch('start_game', player: { name: 'alejandro' }, game: 'chess')
```

## Rails Setup

```bash
rails generate odsl:install
```

This creates:
- `config/initializers/odsl.rb` — configuration file
- `db/migrate/XXXXXX_create_odsl_tables.rb` — audit tables migration

## Optional Runtime Dependencies

Add to your Gemfile as needed:

```ruby
gem "redlock"    # for distributed locking
gem "activejob"  # for background job support via ActiveJob
```

## License

MIT

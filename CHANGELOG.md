# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-10-10

### Added
- Pluggable background adapters: `:thread` (default) and `:active_job`
- `run_in_background(:method)` and `run_in_parallel(*methods)` on service instances
- `Odsl::Configuration` with `background_adapter`, `audit_ttl`, `lock_redis_url`, `lock_ttl`
- `Odsl.configure {}` and `Odsl.config` with thread-safe access
- Step-level audit system: `Odsl::Audit::ExecutionContext` and `Odsl::Audit::StepRecord`
- Idempotent runs via `run(:method, key: "...")` — no-op if already completed
- `resume(key:)` class method — restarts a failed run from the first incomplete step
- TTL support for audit records via `audit_ttl` config option
- `Odsl.cleanup_expired!` and `rake odsl:cleanup` for pruning expired records
- Distributed locking via `lock(*vars)` DSL method (backed by [Redlock](https://github.com/leandromoreira/redlock-rb))
- `Odsl::LockError`, `Odsl::AlreadyRunningError`, `Odsl::ContextNotFoundError`
- Rails generator: `rails generate odsl:install` (migration + initializer)
- `Odsl::Railtie` for automatic Rake task registration in Rails apps
- `Odsl::Audit::Serializer` for JSON-safe step result persistence
- GitHub Actions CI across Ruby 3.1, 3.2, 3.3

### Fixed
- Thread-safe configuration access via `CONFIG_MUTEX`
- `lib/odsl/error.rb` replaced with `lib/odsl/errors.rb` (syntax fix, plural naming)

### Changed
- Minimum Ruby version remains `>= 3.1.0`
- Version bumped to `0.3.0`

## [0.2.0] - 2024-01-01

### Added
- `inmutable` mode
- `run_in_background` / `run_in_parallel`
- `subscribe` / `dispatch` event bus
- `finish_with` / `value_return` aliases
- `set` / `link` aliases for `make` / `call`

## [0.1.0] - 2023-01-01

### Added
- Initial DSL: `build`, `with`, `make`, `call`, `get`, `use`, `instantiate`, `finish_with`
- `Odsl::Dsl` base class
- `inmutable` class-level flag
- Minitest test suite

[Unreleased]: https://github.com/aleguro/ODSL/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/aleguro/ODSL/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/aleguro/ODSL/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/aleguro/ODSL/releases/tag/v0.1.0

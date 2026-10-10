# Contributing to Odsl

Thanks for taking the time to contribute!

## Setup

```bash
git clone https://github.com/aleguro/ODSL.git
cd ODSL
bundle install
```

## Running Tests

```bash
bundle exec rake test
```

The test suite uses an in-memory SQLite database — no external services required.

## Adding a Feature

1. Fork the repo and create a branch: `git checkout -b feat/your-feature`
2. Write a failing test first
3. Implement the feature
4. Run `bundle exec rake test` — all tests must pass
5. Update `README.md` if the public API changed
6. Add an entry to `CHANGELOG.md` under `[Unreleased]`
7. Open a PR against `master`

## Code Style

- No unnecessary comments — let well-named identifiers speak
- No added error handling for scenarios that can't happen
- Prefer editing existing files over creating new ones
- Keep files focused; one clear responsibility per file

## Reporting a Bug

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) and include a minimal reproducible example.

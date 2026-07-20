# 01 — Registry base class

Priority: **high**.
Status: TODO.

## Problem

Five registry classes duplicate an identical pattern:

- `Omnizip::AlgorithmRegistry` (`lib/omnizip/algorithm_registry.rb`)
- `Omnizip::FormatRegistry` (`lib/omnizip/format_registry.rb`)
- `Omnizip::FilterRegistry` (`lib/omnizip/filter_registry.rb`)
- `Omnizip::ChecksumRegistry` (`lib/omnizip/checksum_registry.rb`)
- `Omnizip::OptimizationRegistry` (`lib/omnizip/optimization_registry.rb`)
- `Omnizip::Password::EncryptionRegistry` (`lib/omnizip/password/encryption_registry.rb`)
- `Omnizip::Converter::ConversionRegistry` (`lib/omnizip/converter/conversion_registry.rb`)

Each implements a slightly different version of `register / get /
registered? / available / reset` with different naming, error classes, and
key-normalization rules.

Inconsistencies:

| Registry | Storage | Reset | Not-found error |
|---|---|---|---|
| AlgorithmRegistry | `@algorithms ||= {}` | `reset!` | `UnknownAlgorithmError` |
| FormatRegistry | `@registry ||= {}` | (none) | returns nil |
| FilterRegistry | `@filters = {}` | `reset!` | `UnknownFilterError` |
| ChecksumRegistry | `@checksums = {}` | `clear` | `UnknownAlgorithmError` |
| OptimizationRegistry | `@strategies ||= {}` | `clear!` | `OptimizationNotFound` |
| EncryptionRegistry | `@strategies = {}` | `reset` | `ArgumentError` |
| ConversionRegistry | array of classes | `reset` | returns nil |

None are thread-safe.

## Plan

1. Create `lib/omnizip/registry.rb` defining `Omnizip::Registry` — a
   thread-safe generic registry with:
   - `register(name, value, **opts)` (overrides per subclass)
   - `get(name)` → raises `not_found_error` if missing
   - `registered?(name)` → bool
   - `available` / `all` → keys
   - `reset!` → clears store (canonical name)
   - `Mutex`-synchronized mutations
   - Configurable `not_found_error` class and `normalize_key` hook.

2. Migrate each registry to inherit from `Omnizip::Registry`. Preserve the
   existing public class names and method names so call sites still work.
   For backward compatibility, alias `clear`/`reset` to `reset!`,
   `supported_formats`/`strategies` to `available` where applicable.

3. FormatRegistry keeps `normalize_extension` as its `normalize_key` hook.

4. FilterRegistry keeps its `formats:` registry metadata and
   `get_for_format` / `supports_format?` / `filters_for_format` extensions
   on top of the base.

5. ConversionRegistry is array-based and is the only outlier; leave as-is
   or convert to a key based on `[source, target]` tuple. Pragmatically:
   leave as-is, document why.

## Acceptance

- All existing registry specs pass unchanged.
- `bundle exec rspec` failure count is ≤ baseline (2).
- No new rubocop offenses.
- `lib/omnizip/registry_spec.rb` covers register/get/registered?/reset! and
  thread-safety smoke test.

## Files to touch

- create `lib/omnizip/registry.rb`
- create `spec/omnizip/registry_spec.rb`
- modify `lib/omnizip/algorithm_registry.rb`
- modify `lib/omnizip/format_registry.rb`
- modify `lib/omnizip/filter_registry.rb`
- modify `lib/omnizip/checksum_registry.rb`
- modify `lib/omnizip/optimization_registry.rb`
- modify `lib/omnizip/password/encryption_registry.rb`
- modify `lib/omnizip.rb` to autoload `:Registry`

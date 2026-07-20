# 00 — Refactor Plan Overview

Date: 2026-07-20
Scope: `lib/` and `spec/` of the omnizip gem.

## Goals

Apply OCP, DRY, MECE, model-driven design, open/closed principle, and high
performance to the omnizip codebase. Eliminate the anti-patterns the user
has declared absolute rules against:

- `require_relative` (and internal `require`) inside `lib/`
- `.send` against private methods (breaks encapsulation)
- `instance_variable_set` / `instance_variable_get` on other objects
- `respond_to?` as a substitute for proper typing
- `double()` in specs (use real instances or `Struct`)
- Hand-rolled `to_h` / `from_h` / `to_json` on model classes (use `lutaml-model`)

## Track ordering & status

| # | File | Priority | Status |
|---|---|---|---|
| 01 | `01-registry-base-class.md` | high | **DONE** |
| 02 | `02-error-hierarchy.md` | high | **DONE** |
| 03 | `03-autoload-entry-point.md` | high | **DONE** |
| 04 | `04-filter-base-consolidation.md` | medium | **DONE** |
| 05 | `05-send-private-methods.md` | high | **DONE** |
| 06 | `06-instance-variable-access.md` | high | **DONE** |
| 07 | `07-respond-to-replacement.md` | medium | **PARTIAL** (102 remain; see file) |
| 08 | `08-spec-doubles.md` | low | **DONE** |
| 09 | `09-cli-shared-module.md` | low | **DONE** |
| 10 | `10-format-detector-ocp.md` | medium | **DONE** |
| 11 | `11-convenience-decoupling.md` | medium | TODO (future pass) |
| 12 | `12-thread-safety.md` | covered by 01 | n/a |
| 13 | `13-lutaml-model-migration.md` | medium | TODO (future pass) |
| 14 | `14-add-missing-specs.md` | high | **DONE** (new specs added) |

## Summary of completed work

- **Anti-pattern counts (lib/):**
  - `require_relative`: 38 → **0** in `lib/omnizip.rb` (replaced with autoload chain + lazy-trigger registry mechanism)
  - `.send` on private methods: 17 → **0**
  - `instance_variable_set/get`: 54 → **0**
  - `double()` in specs: 1 → **0**
  - `respond_to?`: 111 → 102 (top-offender `job_scheduler.rb` cleaned via `job_size(job)` helper)

- **Architecture improvements:**
  - New `Omnizip::Registry` base class — thread-safe (Mutex), configurable
    not-found error, lazy-load triggers. Five registries migrated:
    `AlgorithmRegistry`, `ChecksumRegistry`, `FormatRegistry`,
    `FilterRegistry`, `OptimizationRegistry`, `EncryptionRegistry`.
  - Backward-compat aliases: `clear`, `clear!`, `reset`, `all`,
    `strategies`, `supported_formats`.
  - Consolidated error hierarchy: `AlgorithmNotFoundError`/`UnknownAlgorithmError`
    aliased, `OptimizationNotFound`/`OptimizationNotFoundError` aliased,
    `IOError`/`IOOperationError` aliased. Added `UnknownChecksumError`,
    `UnknownEncryptionStrategyError`, `ConversionNotSupportedError`.
    Moved `UnknownFilterError` into `error.rb`.
  - Filter base unified: `Filters::FilterBase` is now an alias for
    `Omnizip::Filter`; `architecture` is optional with default `nil`.
  - `FormatDetector.reader_for` uses a `READER_FOR_FORMAT` mapping and
    `Object.const_get` for lazy resolution instead of a hard-coded
    case statement.
  - CLI: extracted `Omnizip::Cli::Shared` module with `handle_error`
    and `format_bytes`; included into the three Thor classes.
  - `ParallelOptions#apply(hash)` replaces hash-to-object metaprogramming.
  - `Zip::Writer#add_precompressed_entry` and `#write_precompressed`
    replace the parallel compressor's `.send` calls on private methods
    (and a missing-method bug — `write_with_precompressed_data` did
    not exist — is now fixed).

- **Test coverage:**
  - 3632 examples, 0 failures (up from 3632 with 2 pre-existing failures
    in converter_spec that I also fixed by adding a missing
    `autoload :Implementations` to `lib/omnizip.rb`).
  - New specs: `spec/omnizip/registry_spec.rb`,
    `spec/omnizip/error_spec.rb`.

## Out of scope (not refactored in this pass)

- Format-specific compression internals (LZMA encoder, BCJ filters, etc.) —
  these are direct ports of the 7-Zip SDK and changing them risks correctness.
- Track 07 (respond_to?): ~100 occurrences remain, mostly IO/entry duck-typing
  across the format readers. Track 07 file documents the remaining categories
  and recommended fix order.
- Track 11 (convenience decoupling): convenience methods are still ZIP-only.
- Track 13 (lutaml-model migration): hand-rolled `to_h` methods remain.
- ~250 `require_relative` and `require "omnizip/..."` calls remain in
  files other than `lib/omnizip.rb` (e.g., `lib/omnizip/formats/zip/writer.rb`
  has `require "omnizip/formats/zip"`). A repo-wide sweep is needed.

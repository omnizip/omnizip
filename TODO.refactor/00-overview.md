# 00 — Refactor Plan Overview

Date: 2026-07-20 (updated 2026-07-21)
Scope: `lib/` and `spec/` of the omnizip gem.

## Goals

Apply OCP, DRY, MECE, model-driven design, open/closed principle, and high
performance to the omnizip codebase. Eliminate the anti-patterns declared
as absolute rules:

- `require_relative` (and internal `require`) inside `lib/`
- `.send` against private methods (breaks encapsulation)
- `instance_variable_set` / `instance_variable_get` on other objects
- `respond_to?` as a substitute for proper typing
- `double()` in specs (use real instances or `Struct`)
- Hand-rolled `to_h` / `from_h` / `to_json` on model classes (use `lutaml-model`)

## Track status

| # | File | Priority | Status |
|---|---|---|---|
| 01 | `01-registry-base-class.md` | high | **DONE** |
| 02 | `02-error-hierarchy.md` | high | **DONE** |
| 03 | `03-autoload-entry-point.md` | high | **DONE** |
| 04 | `04-filter-base-consolidation.md` | medium | **DONE** |
| 05 | `05-send-private-methods.md` | high | **DONE** |
| 06 | `06-instance-variable-access.md` | high | **DONE** |
| 07 | `07-respond-to-replacement.md` | medium | **PARTIAL** — IO::Source/Sink adapter built; type-check sites converted; ~76 IO capability checks remain in xz_impl/* and ole/* (legitimate duck-typing for ungetbyte / set_encoding etc.) |
| 08 | `08-spec-doubles.md` | low | **DONE** |
| 09 | `09-cli-shared-module.md` | low | **DONE** |
| 10 | `10-format-detector-ocp.md` | medium | **DONE** |
| 11 | `11-convenience-decoupling.md` | medium | **DONE** (ArchiveHandler dispatcher + ZipHandler + TarHandler) |
| 12 | `12-thread-safety.md` | covered by 01 | n/a |
| 13 | `13-lutaml-model-migration.md` | medium | **PARTIAL** — CompressionOptions and AlgorithmMetadata migrated; ConversionOptions pending lutaml symbol-type support |
| 14 | `14-add-missing-specs.md` | high | **DONE** |

## Anti-pattern counts (lib/)

| Pattern | Before | After |
|---|---|---|
| `require_relative` / `require "omnizip/..."` | ~290 | **0** |
| `.send` on private methods | 17 | **0** |
| `instance_variable_set`/`get` | 54 | **0** |
| `double()` in specs | 1 | **0** |
| `respond_to?` | 111 | 76 (mostly IO capability detection) |
| Hand-rolled model `to_h` | 26 | 24 (2 migrated to lutaml-model) |

## Architecture summary

- **`Omnizip::Registry`** — thread-safe base class with lazy-load triggers.
- **`Omnizip::IO::Source` / `Sink`** — polymorphic adapters for
  String/Path/IO/StringIO/Tempfile.
- **`Omnizip::ArchiveHandler`** — dispatcher decoupling Convenience from
  ZIP. New formats plug in by registering a handler.
- **`Omnizip::Platform`** — predicates for symlink/hardlink/NTFS support.
- **Error hierarchy** consolidated with backward-compat aliases.
- **`Filter` / `FilterBase`** unified.

## Test coverage

3643 examples, 0 failures. New specs:

- `spec/omnizip/registry_spec.rb`
- `spec/omnizip/error_spec.rb`
- `spec/omnizip/io/source_spec.rb`
- `spec/omnizip/convenience_tar_spec.rb`

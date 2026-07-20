# 02 — Error hierarchy consolidation

Priority: **high**.
Status: TODO.

## Problems

1. `AlgorithmNotFoundError` and `UnknownAlgorithmError` both exist in
   `lib/omnizip/error.rb` and are used interchangeably. The two registries
   that raise on miss (`AlgorithmRegistry`, `ChecksumRegistry`) both raise
   `UnknownAlgorithmError`.
2. `OptimizationNotFound` lacks the `Error` suffix convention.
3. `Omnizip::IOError` shadows Ruby's built-in `IOError` — confusing for
   users who `rescue IOError`.
4. `UnknownFilterError` is defined at the bottom of
   `lib/omnizip/filter_registry.rb` instead of `lib/omnizip/error.rb`.
5. `EncryptionRegistry` raises vanilla `ArgumentError` instead of a
   domain-specific error.
6. `ConversionRegistry` returns nil instead of raising.

## Plan

1. In `lib/omnizip/error.rb`:
   - Keep `AlgorithmNotFoundError` as canonical; make
     `UnknownAlgorithmError` an alias (subclass) for backward compatibility.
     Document the alias.
   - Rename `OptimizationNotFound` → `OptimizationNotFoundError`. Keep the
     old name as an alias for backward compatibility.
   - Rename `IOError` → `IOOperationError`. Keep `IOError` as an alias for
     backward compatibility (or deprecate it).
   - Add `UnknownFilterError` to `error.rb` (and remove from
     `filter_registry.rb`).
   - Add `UnknownEncryptionStrategyError < Error`.
   - Add `ConversionNotSupportedError < Error`.

2. Update all internal `raise` sites to use the canonical names.

3. Update `FormatRegistry`, `ConversionRegistry` to raise their new errors
   instead of returning nil where the caller cannot reasonably handle nil.

4. Update `lib/omnizip.rb` autoload entries to include the new error names.

## Acceptance

- All existing specs pass.
- No new rubocop offenses.
- `lib/omnizip/error_spec.rb` confirms hierarchy and aliases.

## Files

- modify `lib/omnizip/error.rb`
- modify `lib/omnizip/filter_registry.rb` (remove inline error)
- modify `lib/omnizip/optimization_registry.rb` (raise renamed error)
- modify `lib/omnizip/password/encryption_registry.rb` (raise new error)
- modify `lib/omnizip/converter/conversion_registry.rb` (raise on miss)
- modify `lib/omnizip.rb` autoload list
- create `spec/omnizip/error_spec.rb`

# 05 — Eliminate `.send` against private methods

Priority: **high**.
Status: TODO.

## Rule

> NEVER use `send` to call private methods. Private methods are private
> for a reason. If you need to call it from outside, the API boundary is
> wrong — redesign, don't bypass.

## Inventory (17 occurrences)

| File:Line | Call | Fix |
|---|---|---|
| `lib/omnizip/parity.rb:178` | `verifier.send(:parse_par2_file)` | Promote to public |
| `lib/omnizip/parity.rb:180` | `verifier.send(:calculate_total_blocks)` | Promote to public |
| `lib/omnizip/parity/par2_repairer.rb:174` | `@verifier.send(:find_file_path, ...)` | Promote to public |
| `lib/omnizip/parallel/parallel_compressor.rb:306` | `writer.send(:create_entry, ...)` | Promote to public |
| `lib/omnizip/parallel/parallel_compressor.rb:324` | `writer.send(:write_with_precompressed_data, ...)` | Promote |
| `lib/omnizip/parallel/parallel_compressor.rb:136` | `opts.send(:"#{k}=", v)` | Replace with `CompressionOptions#apply(hash)` |
| `lib/omnizip/parallel/parallel_extractor.rb:110` | `reader.send(:decompress_data, ...)` | Promote to public |
| `lib/omnizip/parallel/parallel_extractor.rb:135` | `opts.send(:"#{k}=", v)` | Same as above |
| `lib/omnizip/formats/format_spec_loader.rb:203` | `format.send(key)` | Replace with explicit dispatch |
| `lib/omnizip/converter/seven_zip_to_zip_strategy.rb:62` | `reader.send(:extract_entry_data, ...)` | Promote to public |
| `lib/omnizip/formats/seven_zip/parser.rb:573` | `entry.send(:"#{attr}=", ...)` | Add public writer or ctor arg |
| `lib/omnizip/formats/rpm/header.rb:36` | `header.send(:parse!, io)` | Promote `parse!` to public |
| `lib/omnizip/algorithms/zstandard/frame/header.rb:72,76,80` | `header.send(:parse_window_descriptor, ...)` etc. | Promote parse helpers to public, or inline |
| `lib/omnizip/zip/file.rb:419` | `@reader.send(:decompress_data, ...)` | Promote to public |
| `lib/omnizip/crypto/aes256/cipher.rb:90` | `cipher.send(mode)` | Replace with explicit `if encrypt? ... else ...` |

## Plan

For each call site, choose ONE of:

1. **Promote the method to public.** If callers legitimately need it, the
   `private` declaration was wrong. Add a doc comment and make it public.
2. **Add a public facade.** Keep the private method, expose a public
   method with a clearer name that wraps it.
3. **Inline the call.** Sometimes the private method is one line and the
   `.send` is just laziness — inline the body.

`opts.send(:"#{k}=", v)` (parallel_compressor.rb:136 and
parallel_extractor.rb:135) deserves a real fix: add
`CompressionOptions#apply(attributes)` and `ParallelOptions#apply` methods
that take a hash and set attributes via `public_send` only on whitelisted
keys.

`format.send(key)` (format_spec_loader.rb:203) is data-driven dispatch on
a spec format — replace with a hash of known keys → lambdas, or with a
case statement that calls public methods explicitly.

`cipher.send(mode)` (crypto/aes256/cipher.rb:90) — replace with an
explicit branch on whether to call `encrypt` or `decrypt`.

## Acceptance

- `grep -rn "\.send(" lib/` returns at most a handful of intentional
  metaprogramming cases (e.g., `public_send` with documented reason).
- All specs pass.

## Files

See table above. 11 files to modify.

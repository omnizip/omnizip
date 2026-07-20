# 06 — Remove `instance_variable_set` / `instance_variable_get`

Priority: **high**.
Status: TODO.

## Rule

> NEVER use `instance_variable_set` or `instance_variable_get`. Accessing
> another object's instance variables breaks encapsulation. If you need
> the data, add a public accessor or rethink the ownership.

## Inventory (54 occurrences)

### `instance_variable_set` (writers)

| File:Line | What | Fix |
|---|---|---|
| `lib/omnizip/formats/rpm/lead.rb:53,66-73` | Sets 9 attrs from a parsed hash in a factory | Replace with ctor args |
| `lib/omnizip/password/zip_crypto_strategy.rb:118` | `crc32.instance_variable_set(:@crc, crc)` | Add `Crc32#reset(crc)` public method |
| `lib/omnizip/formats/iso/reader.rb:161` | Sets `@full_path` on a record | Add public writer or store externally |
| `lib/omnizip/formats/xz_impl/block_decoder.rb:573-574,629-630` | Sets decoder state | Add public setters on LZMA2 decoder |
| `lib/omnizip/algorithms/lzma/xz_utils_decoder.rb:434-435,448,450` | Sets decoder state | Promote to ctor / public setters |
| `lib/omnizip/zip/file.rb:378,387,450` | Sets entry state | Add public setters |
| `lib/omnizip/formats/seven_zip/writer.rb:65,178,196` | Sets writer state | Add public setters |

### `instance_variable_get` (readers)

| File:Line | What | Fix |
|---|---|---|
| `lib/omnizip/parity.rb:181,187` | Reads `@recovery_blocks`, `@file_list` from verifier | Add public readers |
| `lib/omnizip/parallel/parallel_compressor.rb:317` | Reads `@entries` from writer | Add public reader |
| `lib/omnizip/formats/lzma_alone.rb:152-156` | Reads decoder state (`@lc`, `@lp`, `@pb`, `@dict_size`, `@uncompressed_size`) | Add `Decoder#properties` Struct or public attr_readers |
| `lib/omnizip/formats/lzip.rb:149-151` | Reads decoder state | Same pattern |
| `lib/omnizip/formats/iso/reader.rb:180` | Reads `@full_path` | Use the public reader from above |
| `lib/omnizip/formats/msi/string_pool.rb:89` | Reads `@stream_name_map` | Add public reader |
| `lib/omnizip/formats/rar/compression/ppmd/encoder.rb:55` | Reads `@mem_size` from model | Add public reader |
| `lib/omnizip/formats/ole/dirent.rb:157` | Reads `@name_lookup` from parent | Add public reader |
| `lib/omnizip/formats/xz_impl/block_decoder.rb` | (covered above) | |

## Plan

For each hotspot:

1. Add a `attr_reader` (or `attr_accessor` if mutation is legitimate) on
   the target class for the ivar being accessed.
2. Replace `obj.instance_variable_get(:@foo)` with `obj.foo`.
3. For setters: either (a) add a public writer if mutation is part of the
   API contract, or (b) refactor to pass the value through the
   constructor, or (c) add a domain-named method (e.g.,
   `crc.reset(value)` instead of writing `@crc`).

For `lib/omnizip/formats/rpm/lead.rb` (worst offender, 9 ivars set in a
factory): replace the factory with `Lead.new(lead_type:, magic:, ...)`.
Use a Struct or a lutaml-model class.

For decoder state introspection (lzma_alone.rb, lzip.rb,
block_decoder.rb): define a `Decoder::Properties` Struct (or
`Omnizip::Models::DecoderProperties`) and expose it via a single
`decoder.properties` accessor.

## Acceptance

- `grep -rn "instance_variable_set\|instance_variable_get" lib/` returns
  zero matches (or only well-documented exceptions).
- All specs pass.

## Files

~21 files; see table above.

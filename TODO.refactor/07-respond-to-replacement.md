# 07 — Replace `respond_to?` with proper typing

Priority: **medium**.
Status: **DONE**, with one known exception — `algorithms/lzma.rb:200` is a type
check we chose not to convert, not feature detection. See "The one exception".

## Rule

> NEVER use `respond_to?` for type checking. Use `is_a?` for type checks,
> or better yet, design the type hierarchy so the check isn't needed.

## Outcome

`lib/` went from 60 `respond_to?` occurrences to 49:

| | count |
|---|---|
| Converted to a real type check | 11 |
| Retained as genuine feature detection, annotated `# allowed:` | 45 |
| Retained as a **deferred type check**, annotated `# allowed:` | 1 |
| Prose inside doc comments (not code) | 3 |

46 sites carry an `# allowed:` annotation, but they are not all the same kind of
thing. 45 are feature detection on objects we do not control. **One is a type
check we decided not to convert** — counting it with the other 45 would overstate
how complete this track is, so it is broken out here and below.

The three prose occurrences are in `entry.rb`, `io/source.rb` and
`parallel/job_scheduler.rb`, where they document the pattern that was removed.
They are kept deliberately — rewording them so a `grep` returns zero would be
dishonest.

`spec/omnizip/respond_to_annotation_spec.rb` enforces the convention. It lexes
`lib/` with `Ripper` and fails on any `respond_to?` **identifier token** that
lacks a `# allowed: <reason>` **comment token** on its own line or the one
above. Being lexer-based rather than substring-based, a `# allowed:` inside a
string literal cannot satisfy it and a `respond_to?` inside a heredoc cannot
trip it.

Note what that spec does and does not do: it enforces that a reason is
**stated**, not that the reason is **good**. It cannot tell feature detection
from a deferred type check, which is exactly why the one exception is recorded
here in prose rather than left for the spec to imply.

## The governing distinction

A check is a **type check** (convert it) when every runtime type is enumerable
from the source. It is **feature detection** (annotate it) when a third party
can register or pass something we cannot enumerate.

The second half is what this pass got wrong at first. omnizip's world is open:

- `FilterRegistry.register` (`filter_registry.rb:30`) raises only on a nil name
  or nil class. **No inheritance check.**
- `ProfileRegistry.register` (`profile_registry.rb:23`) requires only
  `is_a?(CompressionProfile)`, not membership in the built-in set.
- `ArchiveHandler.register` (`archive_handler.rb:26`) accepts any object.
- The third positional `options` parameter on every `Algorithm#compress` /
  `#decompress` is public and unconstrained.

So a check can look like a type check, and be one inside this repo today, while
still being reachable with a type we cannot name. Those stay, annotated.

## What was converted (11)

| site | conversion |
|---|---|
| `algorithms/registration.rb:22` | guard dropped; `Algorithm.inherited` defines `register_algorithm` on every subclass |
| `algorithms/lzma/xz_utils_decoder.rb:291` | guard dropped; `@range_decoder ||=` runs earlier in the same method |
| `commands/archive_list_command.rb:72`, `:105` | `archive.entries`; the private builder returns one of three readers, all of which expose it |
| `implementations/seven_zip/lzma2/encoder.rb`, `implementations/xz_utils/lzma2/encoder.rb` | both `StringCompat` modules deleted, `byteslice` inlined at all three call sites — see below |
| `commands/archive_extract_command.rb:225` | `archive.is_a?(Omnizip::Zip::File)`; closed 4-way set, only ZIP closes |
| `implementations/xz_utils/lzma2/decoder.rb:420` | guard dropped; `@lzma_decoder` is always an `XzUtilsDecoder`, which exposes `range_decoder` |
| `io/stream_manager.rb:74` | `@source.close if @owned`; `@owned` is only true for a path the manager itself opened as a `File` |
| `algorithms/xz_lzma2.rb:59`, `algorithms/sevenzip_lzma2.rb:64` | routed through `Omnizip::IO::Source.for`, which accepts any `#read` duck |

The String branch in those last two was deliberately **not** routed through the
adapter: `Source::StringSource#read` treats a String that exists on disk as a
file path, so routing it would silently start reading files off disk whenever
input collided with a filename.

### The `StringCompat` modules

Each held `if "".respond_to?(:byteslice)` with a `string.bytes[start, length]`
fallback, under a comment claiming Ruby 3.0-3.1 lacks `String#byteslice`.
**That comment was simply wrong** — `String#byteslice` has existed since Ruby
1.9.3, so the fallback was unreachable on every Ruby that could ever have run
this gem.

Deleting only the `respond_to?` branch would have left a module named `Compat`
whose sole purpose was that branch, forwarding one call to `String#byteslice`
and nothing else — and two of the three call sites still carried a "for Ruby
3.0-3.1 compatibility" comment that would have become a lie. So both modules
were deleted outright and `temp_buffer.byteslice(0, out_pos.value)` inlined at
all three call sites (`xz_utils/lzma2/encoder.rb` ×2,
`seven_zip/lzma2/encoder.rb` ×1).

The separate comment at the two XZ Utils call sites is **kept**: it explains why
`byteslice` rather than `[]`, citing
https://bugs.ruby-lang.org/issues/15985 (the `[]` operator can return extra
bytes around NULs). That reason is real and outlives the compat shim.

## What was retained as feature detection (45)

Grouped by what the object actually is. `algorithms/lzma.rb:200` is deliberately
excluded from these counts and covered in the next section.

- **Caller-supplied IO** (24) — `formats/xz_impl/stream_decoder.rb` (8),
  `formats/xz_impl/block_decoder.rb` (3), `algorithms/lzma/xz_utils_decoder.rb`
  (2), `file_type.rb` (3), `io/source.rb` (4), `io/stream_manager.rb` (2),
  `io/buffered_input.rb`, `io/buffered_output.rb`. Ruby has no `Seekable` or
  `Ungettable` interface to type against; `StringIO`, `File`, `Socket`,
  `Tempfile` and a user's own duck all differ in exactly `seek` / `pos` / `size`
  / `ungetbyte` / `set_encoding` / `close`.
- **Public `options` parameter** (7) — `algorithms/lzma.rb` (4),
  `algorithms/bzip2.rb`, `algorithms/deflate.rb`, `algorithms/zstandard.rb`.
- **Open registries** (4) — `models/filter_config.rb`,
  `commands/profile_show_command.rb`, `convenience.rb` (2).
- **Other caller-supplied objects** (10) — foreign archives and entries in
  `extraction/selective_extractor.rb` (5) and `extraction/filter_chain.rb` (3),
  an output sink in `implementations/seven_zip/lzma/encoder.rb`, and a metadata
  object in `metadata/metadata_validator.rb`.

## The one exception (1)

`algorithms/lzma.rb:200` is annotated *"type check deferred, not feature
detection"*. That annotation is accurate and the code is honest, but it means
**track 07 is complete except for this single site**. It is a type check that
survives, not a capability probe.

```ruby
level = if options.respond_to?(:level)
```

Two unrelated value objects reach `build_encoder_options` carrying `#level`:
`Models::CompressionOptions` and
`Formats::Rar::Rar5::Solid::SolidEncoder::LzmaOptions` (`solid_encoder.rb:95`,
reaching this method from `:52`). They share no ancestor. Rewriting the check to
`is_a?(Models::CompressionOptions)` would send solid-RAR5 compression down the
`else` branch and pin its level to 5 instead of the configured 1–5 — a silent
regression, which is why the conversion was rejected rather than attempted.

**What would close it:** unify `SolidEncoder::LzmaOptions`,
`Compression::LZMA::LzmaOptions` (`rar5/compression/lzma.rb:184`) and
`Models::CompressionOptions` into one type. That is RAR5 work, it breaks
`solid_encoder_spec.rb` and `lzma_spec.rb` assertions on `dict_size`, and
`CompressionOptions` names the attribute `dictionary_size`. Once those are one
type, this site converts to `is_a?` in a single line and track 07 is
unconditionally done.

Three cheaper-looking alternatives were considered and rejected: reaching from
`algorithms/` into `formats/rar/rar5/solid/` with a two-armed `is_a?`; a shared
`LevelledOptions` mixin introduced for exactly two call sites; and replacing
`LzmaOptions` with `CompressionOptions` outright, which the specs block.

## Corrections to the previous version of this document

- The count was **60**, not 109.
- Category B (`job.respond_to?(:size)` in `parallel/job_scheduler.rb`) and
  category E (`opts.respond_to?(:"#{k}=")`) were **already done**.
- Category D was wrong. No `File.respond_to?(:symlink)` / `(:link)` sites
  remained and `link_handler.rb` had none at all. The survivors filed under D
  were `io.respond_to?(:pos)` / `(:seek)` in `file_type.rb`, which are **IO**
  capability checks. The proposed `Platform.seekable?(io)` was rejected:
  seekability is not a platform property, and the helper would still have
  contained `respond_to?`, merely relocated.
- `formats/ole/` contained **zero** occurrences. The capability cluster was
  `formats/xz_impl/` plus `algorithms/lzma/xz_utils_decoder.rb`.
- Category C was partly done already: `Omnizip::Entry` existed and was included
  by 12 entry classes. Converting `extraction/filter_chain.rb` to use it was
  attempted and rejected — below.

## Rejected: converting `extraction/filter_chain.rb`

`FilterChain#extract_filename` still walks `name` / `path` / `filename`. Routing
it through `Omnizip::Entry` looked like the intended fix, but a foreign entry
with `name == "secret.txt"` and `to_s == "opaque"` matches `*.txt` today and
would not afterwards. Because these filters drive **exclusion** as well as
inclusion, a filter that stops matching means a file the caller meant to block
gets extracted. `Extraction.extract_with_filter` is public, so this is
reachable. The conversion needs every entry reaching `FilterChain` to include
`Omnizip::Entry`, which the public API cannot guarantee.

## Bug found while doing this work

Auditing `IO::Source` for this track surfaced a live `NameError` in shipped
code. `io/source.rb` had **no `require` statements at all**, while `Source.for`
and `Sink.for` both `case` on `::IO, ::StringIO, ::Tempfile`. After a bare
`require "omnizip"` neither `StringIO` nor `Tempfile` is defined, so any input
that was not already an `::IO` raised:

```
$ ruby -Ilib -e 'require "omnizip"
                 sink = Object.new; def sink.write(d); end
                 Omnizip::Formats::Xz.create("hello", sink)'
NameError: uninitialized constant Tempfile
```

The adapter had 12 production call sites across `Formats::Xz`, `Formats::Lzip`,
`Formats::LzmaAlone` and `Algorithms::LZMA2`. The failure moved with the caller
— whichever constant the load path happened to pull in first appeared to work —
which is why it survived.

Fixed in its own commit across 15 files: 12 requires added to 11 files that
referenced a constant without requiring it, and 4 requires relocated out of
method and class bodies into the file prologue.

`spec/omnizip/constant_require_spec.rb` enforces the invariant statically —
`Ripper.lex` finds the constant references, `Ripper.sexp` confirms the matching
require is a top-level unconditional statement in the prologue, accepting both
`require "x"` and `require("x")`. `spec/omnizip/clean_load_spec.rb` adds four
subprocess regression proofs. Those must shell out: an in-process example passes
on the broken library, because `spec_helper` and sibling specs load both
constants as a side effect. That is the same masking that hid the bug.

## Acceptance

- `grep -rn "respond_to?" lib/` → 49: 46 annotated code sites (45 feature
  detection + 1 deferred type check) and 3 doc comments.
- `spec/omnizip/respond_to_annotation_spec.rb` passes, and fails loudly on any
  new unannotated occurrence.
- The one deferred type check is tracked in "The one exception" above, not
  quietly folded into the feature-detection count.

## Follow-ups

- Unify `SolidEncoder::LzmaOptions`, `Compression::LZMA::LzmaOptions` and
  `Models::CompressionOptions`, which would let `algorithms/lzma.rb:200`
  convert.
- Normalize algorithm `options` to a single type. `Algorithm.compress(data,
  level: 9)` forwards a Hash, so `bzip2`, `deflate` and `zstandard` silently
  drop the level today — reached from `formats/zip/writer.rb:390`,
  `zip/output_stream.rb:278` and `parallel/parallel_compressor.rb:104`. This
  changes compressed output, so it needs its own pass. It would delete most of
  the `options` annotations.
- Give `FilterChain` a guaranteed `Omnizip::Entry` contract, which would let
  `extract_filename` convert.

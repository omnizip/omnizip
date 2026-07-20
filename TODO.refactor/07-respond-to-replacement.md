# 07 — Replace `respond_to?` with proper typing

Priority: **medium**.
Status: **partial — see Remaining Work**.

## Rule

> NEVER use `respond_to?` for type checking. Use `is_a?` for type checks,
> or better yet, design the type hierarchy so the check isn't needed.

## Done in this pass

- Removed `opts.respond_to?(:"#{k}=")` from `parallel_compressor.rb` and
  `parallel_extractor.rb` by adding `ParallelOptions#apply(hash)` with a
  fixed setter whitelist.
- Removed `format.respond_to?(:metadata)` from
  `optimization_registry.rb` by relying on `Strategy.metadata` being
  defined on the base class.

## Remaining work

109 `respond_to?` occurrences remain in `lib/`. They fall into these
categories (sampled):

### A. Duck-typed IO/String inputs (largest category)

`input.respond_to?(:read)` / `output.respond_to?(:write)` in
`formats/xz.rb`, `formats/lzma_alone.rb`, `formats/lzip.rb`,
`formats/xz_impl/*.rb`, `pipe/*.rb`.

**Fix:** introduce `Omnizip::IO::Source.for(input)` and
`Omnizip::IO::Sink.for(output)` adapter methods in `lib/omnizip/io.rb`
that wrap String / StringIO / File / Pathname behind a single API.
Replace each `respond_to?`-guarded branch with a polymorphic call on the
adapter.

### B. Job-size duck typing

`job.respond_to?(:size)` in `parallel/job_scheduler.rb` (6 occurrences).

**Fix:** define `Parallel::Job` base with `#size` returning a default of
1. Jobs that know their size override; others inherit the default. The
scheduler stops needing to ask.

### C. Entry-type duck typing

`entry.respond_to?(:name)`, `entry.respond_to?(:path)`,
`entry.respond_to?(:filename)`, `entry.respond_to?(:read)`,
`entry.respond_to?(:get_input_stream)` in
`extraction/selective_extractor.rb`, `parallel/parallel_extractor.rb`,
`commands/archive_list_command.rb`, `pipe/stream_decompressor.rb`,
`formats/rar/reader.rb`.

**Fix:** define `Omnizip::Models::Entry` as a common base for
zip/seven_zip/rar/tar entry classes. Each format's entry inherits and
implements the contract (`#name`, `#size`, `#unix_perms`, `#mtime`,
etc., returning nil when not applicable).

### D. Platform feature detection

`File.respond_to?(:symlink)`, `File.respond_to?(:link)`,
`io.respond_to?(:pos)`, `io.respond_to?(:seek)` in `link_handler.rb`,
`file_type.rb`.

**Fix:** add `Platform.symlinks_supported?`,
`Platform.seekable?(io)` predicates in `lib/omnizip/platform.rb`.

### E. Hash-to-object metaprogramming

`opts.respond_to?(:"#{k}=")` — same as ParallelOptions pattern. Fix
case-by-case with whitelisted `apply(hash)` methods.

### F. Reader-specific methods

`reader.respond_to?(:split_reader)`,
`elem.respond_to?(:text)`, `entry.respond_to?(:method)` — these are
narrow cases. Convert to `is_a?` checks against the concrete class, or
introduce a small type hierarchy.

## Recommended execution order

1. Tracks A and D — small, localized, no API change for callers.
2. Track B — single file, base class addition.
3. Track C — larger; needs the Entry base class first.
4. Track E — case-by-case.
5. Track F — case-by-case.

## Acceptance

`grep -rn "respond_to?" lib/` returns zero matches (or each remaining
occurrence is annotated with `# allowed: <reason>`).

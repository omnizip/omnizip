# 11 — Convenience module decoupling

Priority: **medium**.
Status: TODO.

## Problem

`lib/omnizip/convenience.rb` (359 lines) hardcodes `Omnizip::Zip::File`
in 7 method bodies (lines 45, 87, 112, 149, 175, 207, 227) —
`compress_file`, `compress_directory`, `extract_archive`,
`list_archive`, `read_from_archive`, `add_to_archive`,
`remove_from_archive`. The codebase supports 7z, XZ, tar, gzip, bzip2,
RAR, but convenience methods are ZIP-only.

## Plan

1. Add a `format:` keyword argument to each convenience method.
   Default to `:zip` for backward compatibility.
2. Resolve the format handler via `FormatRegistry.get(format)` and
   delegate. If the handler doesn't expose the needed operation, raise a
   clear `UnsupportedFormatError` describing what's missing.
3. Each format handler (zip, seven_zip, tar, gzip, xz, bzip2) should
   implement a shared `Handler` interface with `#add_file`,
   `#add_directory`, `#extract`, `#list`, `#read`, `#remove`. This
   becomes the contract for being usable from `convenience.rb`.

## Acceptance

- Convenience methods accept `format:` and dispatch via registry.
- ZIP path remains the default with no behavior change.
- At least one non-ZIP format (e.g., tar) is wired up end-to-end.

## Scope note

Full format handler interface extraction is large. This pass:
1. Adds the `format:` keyword with ZIP default.
2. Wires tar as a second supported format (simplest after zip).
3. Leaves the remaining formats as documented future work.

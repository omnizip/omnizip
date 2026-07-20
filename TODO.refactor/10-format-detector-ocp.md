# 10 — FormatDetector OCP

Priority: **medium**.
Status: TODO.

## Problem

`lib/omnizip/format_detector.rb:112-123` maps format symbols to reader
classes via a `case` statement. Adding a new format requires modifying
this method — a clear OCP violation. The `FormatRegistry` already
registers each format handler; this case statement duplicates that
knowledge.

## Plan

1. Replace the case statement with a lookup against `FormatRegistry`:
   ```ruby
   def reader_for(format)
     FormatRegistry.get(format) ||
       raise(UnsupportedFormatError, "No reader for #{format}")
   end
   ```
2. Ensure every format that previously appeared in the case statement is
   registered in `FormatRegistry` with its reader class.
3. If a format is detected but its handler hasn't been required yet, the
   registry lookup must trigger autoload — verify the autoload wiring in
   `lib/omnizip.rb` makes this work.

## Acceptance

- `lib/omnizip/format_detector.rb` no longer has a format-specific case.
- All format_detector specs pass.
- A new format can be added by registering it, with zero edits to
  FormatDetector.

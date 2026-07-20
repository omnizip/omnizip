# 03 — Autoload entry point

Priority: **high**.
Status: TODO.

## Problem

`lib/omnizip.rb` lines 99–139 contain 31 `require_relative` calls for
algorithms, filters, checksums, and formats. Per the global rule,
`require_relative` is forbidden inside `lib/`. The justification given is
"these classes self-register at load time" — but self-registration only
needs to happen *before first lookup*, not at gem boot.

Additional inconsistency: line 179 uses `require "omnizip/convenience"`
while similar modules are autoloaded.

## Plan

1. Convert each `require_relative` line in `lib/omnizip.rb` to an autoload
   declaration in the appropriate namespace:

   ```ruby
   module Omnizip
     module Algorithms
       autoload :LZMA, "omnizip/algorithms/lzma"
       autoload :LZMA2, "omnizip/algorithms/lzma2"
       # ...
     end
   end
   ```

2. For self-registering classes, keep the registration call at the bottom
   of each implementation file (`AlgorithmRegistry.register(:lzma, LZMA)`).
   Autoload will load the file on first reference, which triggers
   registration. Tests that pre-populate the registry should reference the
   constant first (e.g., `Omnizip::Algorithms::LZMA`).

3. For files that are currently eager-required because *nothing else*
   references them (only the registration matters), add an explicit
   autoload entry in the right namespace *and* arrange for the constant to
   be referenced on first registry miss. Concretely: change registries to
   trigger autoload by referencing the constant rather than calling
   `register` from the file body. See `08-registry-lazy-trigger.md` if a
   fallback is needed.

4. Replace the trailing `require "omnizip/convenience"` with an autoload
   entry — `autoload :Convenience, "omnizip/convenience"` — and reference
   it lazily where used (or eager-load at the very end of `lib/omnizip.rb`
   via `require "omnizip/convenience"` ONLY if Convenience must extend
   Omnizip at boot; document why).

5. Run specs. If any spec fails because a class never autoloaded, fix by
   adding a `require` at the top of the spec file (specs are NOT subject
   to the no-`require_relative` rule for library code; they ARE subject to
   it for sibling spec files but not for library files).

## Acceptance

- `grep -rn "require_relative" lib/` returns zero matches.
- `grep -rn '^require "omnizip/' lib/` is limited to the convenience
  fallback (documented) and any in-file registration triggers.
- All specs pass.

## Files

- modify `lib/omnizip.rb` (replace lines 99–139 and line 179)
- ensure each `lib/omnizip/algorithms/*.rb`, `lib/omnizip/filters/*.rb`,
  `lib/omnizip/checksums/*.rb`, `lib/omnizip/formats/*.rb` ends with its
  own registration call (most already do).

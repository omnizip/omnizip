# 04 — Filter base consolidation

Priority: **medium**.
Status: TODO.

## Problem

Two parallel base classes exist:

- `Omnizip::Filter` (`lib/omnizip/filter.rb`) — has `architecture` and
  `name` attrs plus `id_for_format(format)`. Used by `BCJ` and `Delta`.
- `Omnizip::Filters::FilterBase` (`lib/omnizip/filters/filter_base.rb`) —
  minimal `encode`/`decode`/`.metadata` stub. Used by `BcjX86`, `BcjArm`,
  `BcjArm64`, `BcjIa64`, `BcjPpc`, `BcjSparc`, `Bcj2`.

They share identical `encode(data, position=0)` / `decode(data,
position=0)` / `.metadata` stubs. `FilterBase` is a subset of `Filter`.

## Plan

1. Keep `Filter` as the canonical base, located at
   `lib/omnizip/filters/base.rb`. Make `architecture` optional (defaults
   to nil).
2. Make `Omnizip::Filters::FilterBase` an alias / subclass of the unified
   base for backward compatibility.
3. Migrate subclasses of `FilterBase` to inherit from the unified base.
4. Delete the body of `lib/omnizip/filters/filter_base.rb`, leaving it as
   a backward-compat alias:
   ```ruby
   require "omnizip/filters/base"
   module Omnizip::Filters
   FilterBase = Filter  # backward-compat alias
   end
   ```
   (or define `FilterBase < Filter` if a true subclass is preferred.)

## Acceptance

- All filter specs pass.
- No public API breaks.
- `lib/omnizip/filter.rb` removed or stubbed to alias.

## Files

- modify `lib/omnizip/filter.rb`
- create or modify `lib/omnizip/filters/base.rb`
- modify `lib/omnizip/filters/filter_base.rb` (alias)
- modify each subclass to inherit from the new base
- add autoload entry in `lib/omnizip/filters.rb`

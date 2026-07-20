# 09 — CLI shared module

Priority: **low**.
Status: TODO.

## Problem

`handle_error` is duplicated verbatim in three Thor classes inside
`lib/omnizip/cli.rb` (lines 81–84, 312–315, 557–560). `format_bytes`
(line 562) is a utility that doesn't belong inside the CLI class.

## Plan

1. Create `lib/omnizip/cli/shared.rb` defining:
   ```ruby
   module Omnizip
     class Cli
       module Shared
         def handle_error(err)
           # ...
         end
         module_function :format_bytes
       end
     end
   end
   ```
2. Each Thor class `include`s `Shared`.
3. Move `format_bytes` out of the CLI class proper; place it in a
   `Omnizip::Cli::Formatters` module (or under `Omnizip::Utils::Bytes` if
   broader use exists).

## Acceptance

- Single definition of `handle_error` and `format_bytes`.
- CLI specs pass.

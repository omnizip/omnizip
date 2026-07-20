# 08 — Remove `double()` from specs

Priority: **low** (1 occurrence).
Status: TODO.

## Rule

> NEVER use `double()` in specs. Use real model instances or lightweight
  Structs.

## Inventory

| File:Line | Code |
|---|---|
| `spec/omnizip/formats/rar/rar5/solid/solid_stream_spec.rb:41` | `stat = double("stat")` |

## Plan

1. Read the spec context to see which `File::Stat` interface the spec
   exercises.
2. Replace with `Struct.new(:mtime, :size, :mode, ...).new(...)` or
   `File::Stat.new(real_path)` if a real file is available.

## Acceptance

- `grep -rn "double(" spec/` returns zero matches.
- Spec passes.

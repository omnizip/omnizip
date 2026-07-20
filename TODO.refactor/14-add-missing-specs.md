# 14 — Add missing specs

Priority: **high**.
Status: TODO.

## Plan

Add or strengthen specs for:

1. `Omnizip::Registry` (new base class from track 01) — register / get /
   registered? / available / reset! / thread-safety smoke test / custom
   not-found error.
2. `Omnizip::Error` hierarchy (track 02) — confirm inheritance and
   aliases.
3. `Omnizip::Cli::Shared` (track 09) — `handle_error` and
   `format_bytes`.
4. `Omnizip::IO::Source` / `Omnizip::IO::Sink` (track 07) — adapter
   behavior for String / StringIO / File / Pathname.
5. Promoted public methods (track 05) — wherever a method moves from
   private to public, ensure a spec covers its new visibility.

## Acceptance

- All new specs pass.
- No `double()` introduced.

# Domain Glossary

Names for the concepts that keep coming up in omnizip. Use these
words in code, docs, and reviews; when a term sharpens, update it
here.

## Archive access

- **Archive facade** — `Omnizip::Archive`: the format-neutral entry
  point. `create` yields a Builder (add_file/add_directory/add_data),
  `open` yields a ReaderSession (entries/read/extract/extract_all).
- **ArchiveHandler** — per-format adapter registered in the handler
  registry (create/extract_to/list/read_entry) plus its extension
  route. The facade and the convenience layer dispatch through
  handlers, never through format classes directly.
- **Extension route** — mapping from a file extension to a format
  symbol. Writable routes (`ARCHIVE_FORMAT_EXTENSIONS`) may create
  archives; read routes (`READ_ARCHIVE_FORMAT_EXTENSIONS`) only
  extract/list/read. `.rar` is a writable route (its handler
  creates unrar-verified STORE archives); `.cpio`, `.iso` remain
  read-only routes.

## Reading and decode

- **Reader invariant — always usable** — every Reader
  (`Formats::Zip`, `Formats::SevenZip`, `Formats::Rar`) parses on
  first use; calling `#open` first is never required, only eager.

- **Native decode** — decompression implemented in Ruby inside
  omnizip. RAR native decode is **CRC-gated**: the stored header CRC
  must match the decoded bytes or the result is discarded.
- **External fallback** — delegating to an external tool (the unrar
  command) when native decode cannot be trusted. RAR extraction
  spills the archive once per archive path (the **extraction spill
  cache**) and copies entries out of it.

## Writing and interop

- **Interop-verified** — output accepted by the official tool for
  the format (unrar for RAR, 7zz for 7z/ISO, unzip for ZIP), checked
  with `test` plus a byte-identical extraction round-trip.
- **Omnizip-internal codec** — a compression stream only omnizip can
  decode (RAR methods above :store). Archives carrying them must be
  labeled honestly; official tools fail loudly, never silently.
- **STORE** — the uncompressed method; the interoperability floor
  for every archive writer in this library.

## Seams

- **Compat seam** — `Omnizip::Zip` (aliased into the global `Zip`
  namespace by `omnizip/rubyzip_compat`): a rubyzip-compatible
  layer for library consumers migrating off rubyzip. Internal code
  must use the native `Formats::Zip` tree instead; the Metadata
  subsystem is its one deliberate in-house consumer (in-place
  central-directory editing).
- **Bridge** — an adapter that carries a file-based implementation
  across to a non-file interface, spilling through a temporary file
  (the RAR3/RAR5 legacy readers, `Buffer::SevenZipBridge`).
- **Primary parser** — the one parser per format family verified
  against real archives (e.g. `Formats::Rar::Reader`). Legacy
  interfaces are adapters over primary parsers, never parallel
  implementations.

## In memory

- **Buffer** — `Omnizip::Buffer`: in-memory archive create/read for
  ZIP (stream-based) and 7z (through the bridge). Format detection
  compares binary magic literals.

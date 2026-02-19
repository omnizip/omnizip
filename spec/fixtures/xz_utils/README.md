# XZ Utils Reference Test Files

## Overview

These test files are copied from the XZ Utils reference implementation test suite.
They are used to validate Omnizip's XZ decoder compatibility with the gold standard
implementation.

## Source

**Location**: `/Users/mulgogi/src/external/xz/tests/files/`

XZ Utils is the authoritative reference implementation for the XZ container format.
Using their test files ensures our implementation is compatible with the standard.

## Directory Structure

### good/ - Valid XZ Files (22 files)

These files are well-formed XZ archives that should decode successfully.

**Naming pattern**: `good-*.xz`

**Examples**:
- `good-1-lzma2-1.xz` through `good-1-lzma2-5.xz` - Various LZMA2 compressed files
- `good-1-arm64-lzma2-1.xz` - ARM64 BCJ filter + LZMA2 (not supported in XZ format yet)
- `good-1-delta-lzma2.tiff.xz` - Delta filter + LZMA2 applied to TIFF image
- `good-1-3delta-lzma2.xz` - Multiple delta filters in chain
- `good-1-empty-bcj-lzma2.xz` - BCJ filter edge case (empty input)
- `good-2-lzma2.xz` - Multi-block LZMA2 archive
- `good-1-block-header-*.xz` - Various valid block header configurations
- `good-1-check-*.xz` - Various checksum types (CRC32, CRC64, SHA256, None)

**Expected behavior**: All should decode without errors.

### bad/ - Malformed XZ Files (42 files)

These files have intentional errors that should cause the decoder to fail.

**Naming pattern**: `bad-*.xz`

**Error categories**:
- `bad-0-*.xz` - Stream-level errors (header magic, backward size, etc.)
- `bad-1-*.xz` - Block-level errors (block header, filters, checksums)
- `bad-1-lzma2-*.xz` - LZMA2-specific encoding errors
- `bad-1-check-*.xz` - Checksum errors
- `bad-1-vli-*.xz` - VLI (Variable Length Integer) encoding errors
- `bad-2-*.xz` - Index and padding errors
- `bad-3-*.xz` - Overflow and edge case errors

**Expected behavior**: All should raise `Omnizip::Error` (or subclass) with descriptive message.

### unsupported/ - Unsupported Features (5 files)

These files use valid XZ format but features that Omnizip doesn't support yet.

**Files**:
- `unsupported-filter_flags-*.xz` - Filter flag combinations we don't handle
- `unsupported-block_header.xz` - Block header with unsupported configuration
- `unsupported-check.xz` - Checksum type we don't support

**Expected behavior**: Should raise clear error like "Filter not supported" or "Check type not implemented".

## Test Categories

### LZMA2 Compression Tests
- `good-1-lzma2-1.xz` through `good-1-lzma2-5.xz` - Various LZMA2 configurations
- `good-2-lzma2.xz` - Multi-block archive

### Filter Tests
- `good-1-empty-bcj-lzma2.xz` - BCJ filter with empty input
- `good-1-arm64-lzma2-*.xz` - ARM64 BCJ (not in XZ format, should fail)
- `good-1-delta-lzma2.tiff.xz` - Delta filter preprocessing
- `good-1-3delta-lzma2.xz` - Multiple delta filters

### Checksum Tests
- `good-1-check-crc32.xz` - CRC32 checksum
- `good-1-check-crc64.xz` - CRC64 checksum
- `good-1-check-sha256.xz` - SHA256 checksum
- `good-1-check-none.xz` - No checksum

### Block Header Tests
- `good-1-block-header-1.xz` through `good-1-block-header-3.xz` - Various valid headers
- `bad-1-block-header-*.xz` - Various invalid headers

### Error Detection Tests
- `bad-0-header_magic.xz` - Invalid XZ magic bytes
- `bad-0-footer_magic.xz` - Invalid footer magic
- `bad-1-check-*.xz` - Corrupted checksums
- `bad-1-lzma2-*.xz` - Invalid LZMA2 streams
- `bad-1-stream_flags-*.xz` - Invalid stream flags
- `bad-2-index-*.xz` - Invalid index structures

## File Count Summary

| Category | Files | Purpose |
|----------|-------|---------|
| good/ | 22 | Valid XZ files |
| bad/ | 42 | Malformed XZ files |
| unsupported/ | 5 | Valid but unsupported features |
| **Total** | **69** | |

## Usage in Tests

See: `spec/omnizip/formats/xz/xz_utils_test_suite_spec.rb`

Basic pattern:
```ruby
# Good files should decode
data = File.binread("spec/fixtures/xz_utils/good/good-1-lzma2-1.xz")
result = Omnizip::Formats::Xz.decode(data)
expect(result).to be_a(String)

# Bad files should raise errors
data = File.binread("spec/fixtures/xz_utils/bad/bad-0-header_magic.xz")
expect { Omnizip::Formats::Xz.decode(data) }.to raise_error(Omnizip::Error)
```

## Maintenance

When XZ Utils is updated, check for new test files:
```bash
cd /Users/mulgogi/src/external/xz
git pull
ls -la tests/files/*.xz
```

Copy any new test files to appropriate category directories.

## References

- XZ Utils: https://tukaani.org/xz/
- XZ Utils source: `/Users/mulgogi/src/external/xz/`
- XZ format specification: In `src/liblzma/api/lzma/container.h`

## Notes

1. **ARM64 BCJ**: Files like `good-1-arm64-lzma2-*.xz` contain ARM64 BCJ filters.
   XZ Utils doesn't support ARM64 BCJ in XZ format yet. These tests should
   correctly fail with "not implemented" errors.

2. **Delta Filter**: Files like `good-1-delta-lzma2.tiff.xz` use delta preprocessing.
   This is supported by XZ Utils and should be supported by Omnizip.

3. **Multiple Filters**: `good-1-3delta-lzma2.xz` demonstrates multiple filters
   in a chain (up to 4 allowed in XZ format).

4. **Edge Cases**: Many `bad-*.xz` files test edge cases like:
   - Empty archives
   - Maximum sizes
   - Boundary conditions
   - Corrupted data

## Last Updated

2025-01-24 - Initial copy from XZ Utils test suite

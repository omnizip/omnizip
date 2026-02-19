# XZ Bidirectional Compatibility Test Results

## Test Environment
- **XZ Version**: 5.8.2
- **Ruby Version**: 3.3.2
- **Test Date**: 2025-01-13
- **Test File**: spec/omnizip/formats/xz/xz_compatibility_spec.rb

## Summary
- **Total Tests**: 19 examples
- **Passing**: 6 examples (31.6%)
- **Failing**: 13 examples (68.4%)

## Passing Tests

### XZ → Omnizip Direction (xz encoder, Omnizip decoder)
1. ✅ Empty files
2. ✅ Single byte files
3. ✅ No compression (xz -0)

### Omnizip → XZ Direction (Omnizip encoder, xz decoder)
1. ✅ Empty files
2. ✅ Single byte files
3. ✅ Test environment information

## Failing Tests

### Issue 1: LZMA2 Encoder Bug (Known Blocker)
**Affected Tests**:
- Omnizip → XZ for files ≥100 bytes
- Round-trip tests for any meaningful data
- Large file tests (1MB)

**Symptoms**:
```
xz: (stdin): Compressed data is corrupt
```

**Root Cause**: The LZMA2 encoder produces files that xz cannot decode for data >100 bytes.

**Status**: Known blocker documented in CLAUDE.md under "Current Blocker (v0.3.0)"

**Reference**: See `lib/omnizip/algorithms/lzma2/encoder.rb`

---

### Issue 2: CRC64 Checksum Mismatch
**Affected Tests**:
- XZ → Omnizip for compressed files (xz -1 through xz -9)
- Large files with compression

**Symptoms**:
```
RuntimeError: Block checksum mismatch for check type 4
```

**Root Cause**: The CRC64 calculation in Omnizip's decoder differs from xz's implementation.

**Status**: Decoder bug - needs investigation

**Reference**: See `lib/omnizip/formats/xz_impl/block_decoder.rb:156`

---

### Issue 3: Large File Handling
**Affected Tests**:
- 1MB file tests in both directions

**Symptoms**:
```
RuntimeError: Uncompressed size mismatch: header says 1048576, got 65536
```

**Root Cause**: The decoder doesn't properly handle files that produce multiple LZMA2 chunks.

**Status**: Decoder bug - needs chunk aggregation logic

**Reference**: See `lib/omnizip/formats/xz_impl/block_decoder.rb:150`

---

## Data Patterns Tested

| Pattern | Description | Status |
|---------|-------------|--------|
| empty | Empty string | ✅ PASS |
| single_char | Single character "a" | ✅ PASS |
| short_text | "Hello, World!" | ❌ FAIL (encoder bug) |
| long_text | Repeated paragraph | ❌ FAIL (encoder bug) |
| numeric | Repeated digits | ❌ FAIL (encoder bug) |
| mixed | Alphanumeric with symbols | ❌ FAIL (encoder bug) |
| repetitive | Highly compressible data | ❌ FAIL (encoder + checksum) |
| alternating | "AB" pattern | ❌ FAIL (encoder bug) |
| newlines | Text with line breaks | ❌ FAIL (encoder bug) |
| binary | All byte values (0-255) | ❌ FAIL (encoder bug) |
| random | 1000 bytes of random data | ❌ FAIL (encoder bug) |

## Data Sizes Tested

| Size | Status | Notes |
|------|--------|-------|
| 0 bytes | ✅ PASS | Empty file |
| 1 byte | ✅ PASS | Single character |
| 10 bytes | ✅ PASS | Short text |
| 50 bytes | ❌ FAIL | LZMA2 encoder bug |
| 100 bytes | ❌ FAIL | LZMA2 encoder bug |
| 500 bytes | ❌ FAIL | LZMA2 encoder bug |
| 1000 bytes | ❌ FAIL | LZMA2 encoder bug |
| 5000 bytes | ❌ FAIL | LZMA2 encoder bug |
| 10000 bytes | ❌ FAIL | LZMA2 encoder bug |
| 1 MB | ❌ FAIL | Encoder bug + chunk handling |

## Recommendations

### High Priority
1. **Fix LZMA2 encoder** - This is the main blocker preventing Omnizip → XZ compatibility
   - Current work uses uncompressed LZMA2 chunks for compatibility
   - Need to complete the XZ Utils LZMA2 encoder port

### Medium Priority
2. **Fix CRC64 checksum** - Required for XZ → Omnizip compatibility
   - Verify CRC64 implementation against xz source
   - Add unit tests for CRC64 edge cases

3. **Fix large file handling** - Add proper chunk aggregation
   - Decoder needs to accumulate data from multiple LZMA2 chunks
   - Test with multi-chunk files

### Low Priority
4. **Add more compression level tests** - Currently testing xz -0 through xz -9
5. **Test with filters** - BCJ, Delta filters not yet tested
6. **Performance benchmarks** - Compare compression ratios and speed

## Test Commands

```bash
# Run XZ compatibility tests
bundle exec rspec spec/omnizip/formats/xz/xz_compatibility_spec.rb

# Run all XZ tests
bundle exec rspec spec/omnizip/formats/xz/

# Run specific test pattern
bundle exec rspec spec/omnizip/formats/xz/xz_compatibility_spec.rb:120
```

## Related Files

- Test suite: `spec/omnizip/formats/xz/xz_compatibility_spec.rb`
- LZMA2 encoder: `lib/omnizip/algorithms/lzma2/encoder.rb`
- LZMA2 decoder: `lib/omnizip/algorithms/lzma2/decoder.rb`
- XZ format: `lib/omnizip/formats/xz.rb`
- Stream decoder: `lib/omnizip/formats/xz_impl/stream_decoder.rb`
- Block decoder: `lib/omnizip/formats/xz_impl/block_decoder.rb`

## Notes

- Tests skip gracefully if `xz` utility is not available
- Tests use Open3.capture3 for safe process execution
- Tests create temporary files for xz -t and xz -l validation
- All binary data is handled with proper encoding (ASCII-8BIT)

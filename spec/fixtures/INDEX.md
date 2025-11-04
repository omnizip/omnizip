# Test Fixtures Index

## Overview

All test fixtures are organized by source project with proper attribution.
Each source directory contains a README.adoc file with detailed licensing
and attribution information.

## Sources

Test fixtures in this directory are sourced from reputable open-source
projects to ensure compatibility and correctness across various archive
formats and implementations.

### seven_zip/

Fixtures from the 7-Zip project for .7z format compatibility testing.

* **Project**: 7-Zip
* **URL**: https://www.7-zip.org/
* **License**: GNU LGPL + unRAR license restriction
* **Author**: Igor Pavlov

See [`seven_zip/README.adoc`](seven_zip/README.adoc) for full attribution.

**Files**:
- `simple_lzma.7z` - Basic LZMA compression
- `simple_lzma2.7z` - LZMA2 compression
- `with_directory.7z` - Directory structure
- `multi_file.7z` - Multiple files
- `simple_copy.7z` - Store method (no compression)

### libarchive/

Fixtures from the libarchive project for TAR, CPIO, ISO, and RAR format testing.

* **Project**: libarchive
* **URL**: https://www.libarchive.org/
* **License**: BSD 2-Clause License
* **Maintainer**: Tim Kientzle and contributors

See [`libarchive/README.adoc`](libarchive/README.adoc) for full attribution.

**Subdirectories**:
- `tar/` - TAR format variants (basic, GNU, PAX, with links, sparse files)
- `cpio/` - CPIO formats (binary, newc, crc, odc)
- `iso/` - ISO 9660 (basic, Rock Ridge, Joliet, UDF)
- `rar/` - RAR v3 and RAR v5 test files

### peazip/

Fixtures from the PeaZip project for encryption and multi-format testing.

* **Project**: PeaZip
* **URL**: https://peazip.github.io/
* **License**: GNU LGPL
* **Author**: Giorgio Tani

See [`peazip/README.adoc`](peazip/README.adoc) for full attribution.

**Subdirectories**:
- `encrypted/` - Various encryption methods (AES-256, Twofish, ZipCrypto)
- `multi_format/` - Multi-format test files
- `special_cases/` - Edge cases (long filenames, Unicode, nested archives)

### zipxtract/

Fixtures from the ZipXtract project for ZIP extraction edge cases.

* **Project**: ZipXtract
* **Repository**: https://github.com/VOIDX66/ZipXtract
* **License**: Apache License 2.0
* **Author**: VOIDX66

See [`zipxtract/README.adoc`](zipxtract/README.adoc) for full attribution.

**Subdirectories**:
- `android_test_cases/` - Android-specific archive scenarios
- `multipart/` - Multi-part ZIP archives
- `edge_cases/` - Unusual ZIP structures and edge cases

### zip/

Standard ZIP format test files for basic compatibility testing.

**Files**:
- `simple_deflate.zip` - Basic DEFLATE compression
- `no_compression.zip` - Store method (no compression)
- `with_directory.zip` - Directory structure
- `multi_file.zip` - Multiple files
- `large_text.zip` - Large text file compression

## License Compliance

All fixtures are used in compliance with their respective licenses:

| Source | License | Type |
|--------|---------|------|
| 7-Zip | GNU LGPL + unRAR restriction | Copyleft |
| libarchive | BSD 2-Clause | Permissive |
| PeaZip | GNU LGPL | Copyleft |
| ZipXtract | Apache 2.0 | Permissive |

## Attribution

We gratefully acknowledge the work of:

* **Igor Pavlov** - 7-Zip project
* **Tim Kientzle and contributors** - libarchive project
* **Giorgio Tani** - PeaZip project
* **VOIDX66** - ZipXtract project

Their test suites and implementations help ensure Omnizip maintains
compatibility with industry-standard archive formats and tools.

## Adding New Fixtures

When adding new test fixtures:

1. Place files in the appropriate source directory
2. Use descriptive names indicating the test case
3. Keep files small (< 100 KB when possible)
4. Update the source's README.adoc with new fixtures
5. Update this index with new fixtures
6. Ensure proper attribution and license compliance

## Fixture Requirements

All test fixtures must:

1. Be redistributable under their source license
2. Have known contents for verification
3. Be small enough for fast test execution
4. Cover edge cases and format variations
5. Include both valid and invalid archives for error testing

## Usage in Tests

Fixtures are referenced in RSpec tests using relative paths:

```ruby
RSpec.describe Omnizip::Formats::SevenZip do
  let(:fixture_path) { 'spec/fixtures/seven_zip/simple_lzma.7z' }

  it 'reads 7z archives' do
    # Test implementation
  end
end
```

## Notes

- Binary fixtures are tracked with Git LFS where appropriate
- Large fixtures (> 1 MB) should be generated on-demand in tests
- All fixtures should have corresponding test cases
- Invalid/malformed fixtures are prefixed with `invalid_` or `corrupt_`
- Encrypted fixtures should document the password in comments

## Maintenance

This index should be updated whenever:

- New fixtures are added
- Fixtures are removed or renamed
- Source attribution changes
- Format specifications are updated
- New source projects are integrated

## Fixture Generation

Some fixtures can be generated on-demand using the source tools:

```bash
# Generate 7z fixture with 7-Zip
7z a -t7z -m0=lzma2 test.7z file.txt

# Generate TAR fixture with libarchive
bsdtar -cf test.tar file.txt

# Generate encrypted ZIP with password
zip -e -P password encrypted.zip file.txt
```

Refer to each source's README.adoc for specific generation instructions
and requirements.
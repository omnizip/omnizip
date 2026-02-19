# Official RAR Test Fixtures

Generated using official RAR tool (v7.12) for compatibility testing.

## Generation Commands

All archives created with `-ep1` flag to exclude base directory from paths.

```bash
# Test data files
cd spec/fixtures/rar/official
mkdir -p testdata
echo -e "Hello, RAR World!\nHello, RAR World!" > testdata/test.txt
echo "Binary content for testing" > testdata/binary.dat
dd if=/dev/urandom of=testdata/random.bin bs=1024 count=10

# STORE (m0) - No compression
rar a -m0 -ep1 store_method.rar testdata/test.txt

# FASTEST (m1) - Fast LZ77+Huffman
rar a -m1 -ep1 fastest_method.rar testdata/test.txt

# NORMAL (m3) - Standard LZ77+Huffman (default)
rar a -m3 -ep1 normal_method.rar testdata/test.txt

# BEST (m5) - PPMd (maximum compression)
rar a -m5 -ep1 best_method.rar testdata/test.txt

# Multi-file archive
rar a -m3 -ep1 multifile.rar testdata/*.txt testdata/*.dat

# Solid archive
rar a -m3 -s -ep1 solid.rar testdata/*
```

## Verification

All archives verified with `unrar t <archive>` before committing:

```bash
for f in *.rar; do
  echo "Testing $f"
  unrar t "$f" || echo "FAILED: $f"
done
```

## Archive Details

| Filename | Method | Files | Size | Purpose |
|----------|--------|-------|------|---------|
| `store_method.rar` | STORE (m0) | 1 | 113B | No compression test |
| `fastest_method.rar` | FASTEST (m1) | 1 | 113B | Fast compression test |
| `normal_method.rar` | NORMAL (m3) | 1 | 113B | Standard compression test |
| `best_method.rar` | BEST (m5) | 1 | 113B | PPMd compression test |
| `multifile.rar` | NORMAL (m3) | 2 | 185B | Multi-file archive test |
| `solid.rar` | NORMAL (m3) | 3 | 10K | Solid compression test |

## Usage

These fixtures are used in:
- `spec/omnizip/formats/rar/official_compatibility_spec.rb`
- Tests verify Omnizip can read official RAR archives
- Tests verify official tools can read Omnizip archives

## Notes

- RAR 7.12 creates RAR5 format by default
- All archives contain UTF-8 text and binary data
- Solid archive has all files compressed together for better ratios

#!/bin/bash
# Script to create .7z test fixtures for testing

set -e

FIXTURES_DIR="spec/fixtures/seven_zip"
mkdir -p "$FIXTURES_DIR"

# Create temp directory for test files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Creating test files in $TEMP_DIR..."

# Create test content
echo "Hello, 7-Zip!" > "$TEMP_DIR/hello.txt"
echo "This is a test file for .7z format reading" > "$TEMP_DIR/test.txt"
echo "Line 1" > "$TEMP_DIR/file1.txt"
echo "Line 2" > "$TEMP_DIR/file2.txt"
echo "Line 3" > "$TEMP_DIR/file3.txt"

mkdir -p "$TEMP_DIR/subdir"
echo "Nested file" > "$TEMP_DIR/subdir/nested.txt"

echo "Creating .7z test fixtures..."

# Simple archive with copy (no compression)
echo "  - simple_copy.7z (copy, no compression)"
7z a -mx=0 "$FIXTURES_DIR/simple_copy.7z" "$TEMP_DIR/hello.txt" >/dev/null

# Archive with LZMA compression
echo "  - simple_lzma.7z (LZMA)"
7z a -m0=lzma "$FIXTURES_DIR/simple_lzma.7z" "$TEMP_DIR/test.txt" >/dev/null

# Archive with LZMA2 compression
echo "  - simple_lzma2.7z (LZMA2)"
7z a -m0=lzma2 "$FIXTURES_DIR/simple_lzma2.7z" "$TEMP_DIR/test.txt" \
  >/dev/null

# Multi-file archive
echo "  - multi_file.7z (multiple files)"
7z a "$FIXTURES_DIR/multi_file.7z" "$TEMP_DIR/file1.txt" \
  "$TEMP_DIR/file2.txt" "$TEMP_DIR/file3.txt" >/dev/null

# Archive with directory structure
echo "  - with_directory.7z (with subdirectory)"
7z a "$FIXTURES_DIR/with_directory.7z" "$TEMP_DIR/hello.txt" \
  "$TEMP_DIR/subdir/" >/dev/null

echo "Created fixtures in $FIXTURES_DIR/"
ls -lh "$FIXTURES_DIR/"
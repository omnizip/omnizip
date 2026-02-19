# XAR Format Implementation

## Overview

This document describes the XAR (eXtensible ARchive) format implementation in Omnizip. XAR is primarily used on macOS for software packages (.pkg files), OS installers, and software distribution.

## Format Structure

XAR archives have a simple structure:

```
+-------------------+
| Header (28 bytes) |  Magic, sizes, checksum type
+-------------------+
| Compressed TOC    |  GZIP-compressed XML
+-------------------+
| TOC Checksum      |  SHA1 (20 bytes) or MD5 (16 bytes)
+-------------------+
| File Data Heap    |  Compressed file contents
+-------------------+
```

### Header Format (28 bytes)

| Offset | Size | Field               | Description                         |
|--------|------|---------------------|-------------------------------------|
| 0      | 4    | magic               | 0x78617221 ("xar!" in big-endian)   |
| 4      | 2    | header_size         | Header size (28)                    |
| 6      | 2    | version             | Format version (1)                  |
| 8      | 8    | toc_compressed_size | Size of compressed TOC              |
| 16     | 8    | toc_uncompressed_size | Size of uncompressed TOC          |
| 24     | 4    | checksum_algorithm  | Checksum type (0=none, 1=sha1, 2=md5) |

### Extended Header Format (64 bytes)

For custom checksums (sha256, sha384, sha512):

| Offset | Size | Field               | Description                         |
|--------|------|---------------------|-------------------------------------|
| 0-27   | 28   | (standard header)   | Standard header fields              |
| 28     | 36   | checksum_name       | Null-terminated checksum name       |

## Table of Contents (TOC)

The TOC is a GZIP-compressed XML document:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<xar>
  <toc>
    <creation-time>1609459200.0</creation-time>
    <checksum style="sha1">
      <offset>0</offset>
      <size>20</size>
    </checksum>
    <file id="1">
      <name>example.txt</name>
      <type>file</type>
      <mode>0644</mode>
      <uid>1000</uid>
      <gid>1000</gid>
      <size>1234</size>
      <data>
        <offset>0</offset>
        <size>567</size>
        <length>1234</length>
        <encoding style="application/x-gzip"/>
        <archived-checksum style="sha1">abc123...</archived-checksum>
        <extracted-checksum style="sha1">def456...</extracted-checksum>
      </data>
    </file>
  </toc>
</xar>
```

### File Types

- `file` - Regular file
- `directory` - Directory
- `symlink` - Symbolic link
- `hardlink` - Hard link
- `fifo` - Named pipe
- `block` - Block device
- `character` - Character device
- `socket` - Unix socket

### Compression Types

| MIME Type              | Compression |
|------------------------|-------------|
| application/octet-stream | None      |
| application/x-gzip     | GZIP       |
| application/x-bzip2    | BZIP2      |
| application/x-lzma     | LZMA       |
| application/x-xz       | XZ         |

### Checksum Types

| Algorithm | TOC Code | Size (bytes) |
|-----------|----------|--------------|
| none      | 0        | 0            |
| sha1      | 1        | 20           |
| md5       | 2        | 16           |
| sha224    | 3        | 28           |
| sha256    | 3        | 32           |
| sha384    | 3        | 48           |
| sha512    | 3        | 64           |

## API Usage

### Creating Archives

```ruby
require 'omnizip'

# Create archive with default options (gzip, sha1)
Omnizip::Formats::Xar.create('archive.xar') do |xar|
  xar.add_file('document.pdf')
  xar.add_directory('resources/')
  xar.add_symlink('link_to_doc', 'document.pdf')
  xar.add_data("content", "data/file.txt")
end

# Create with specific options
Omnizip::Formats::Xar.create('archive.xar',
  compression: 'bzip2',
  toc_checksum: 'sha256',
  file_checksum: 'sha256',
  compression_level: 9
) do |xar|
  xar.add_tree('/path/to/directory')
end
```

### Reading Archives

```ruby
# List entries
entries = Omnizip::Formats::Xar.list('archive.xar')
entries.each do |entry|
  puts "#{entry.name} (#{entry.size} bytes)"
  puts "  Type: #{entry.type}"
  puts "  Mode: #{entry.mode}"
end

# Read specific file data
Omnizip::Formats::Xar.open('archive.xar') do |xar|
  entry = xar.get_entry('document.pdf')
  data = xar.read_data(entry)
  puts data.bytesize
end
```

### Extracting Archives

```ruby
# Extract all files
Omnizip::Formats::Xar.extract('archive.xar', 'output/')

# Extract with block for progress
Omnizip::Formats::Xar.open('archive.xar') do |xar|
  xar.entries.each do |entry|
    puts "Extracting #{entry.name}..."
    xar.extract_entry(entry, 'output/')
  end
end
```

## Implementation Details

### Classes

- `Omnizip::Formats::Xar` - Main module with convenience methods
- `Omnizip::Formats::Xar::Reader` - Archive reader
- `Omnizip::Formats::Xar::Writer` - Archive writer
- `Omnizip::Formats::Xar::Header` - Binary header handling
- `Omnizip::Formats::Xar::Toc` - XML TOC parsing/generation
- `Omnizip::Formats::Xar::Entry` - File entry model

### Dependencies

The implementation uses only Ruby standard library:

- `zlib` - GZIP compression for TOC
- `digest` - Checksums (MD5, SHA1, SHA256, etc.)
- `rexml/document` - XML parsing

For file compression, uses existing Omnizip algorithms:

- `Omnizip::Algorithms::Bzip2` - BZIP2 compression
- `Omnizip::Algorithms::Lzma` - LZMA compression
- `Omnizip::Formats::Xz` - XZ compression

## Compatibility

### libarchive Compatibility

The implementation is compatible with libarchive's XAR support:

- All libarchive test fixtures parse correctly
- Archives created can be extracted by libarchive
- Supports all compression and checksum methods

### macOS Compatibility

XAR is the native archive format for:

- macOS Installer packages (.pkg)
- macOS Software Update
- Xcode downloads

## References

- XAR format specification: https://mackyle.github.io/xar/
- libarchive XAR implementation: `archive_read_support_format_xar.c`
- XAR project: https://github.com/mackyle/xar

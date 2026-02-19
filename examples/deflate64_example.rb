#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "omnizip"

# Example: Using Deflate64 compression algorithm
#
# Deflate64 (Enhanced Deflate) extends standard Deflate with:
# - 64KB sliding window (vs 32KB)
# - Better compression for large files
# - ZIP compression method 9

puts "=" * 60
puts "Deflate64 Algorithm Example"
puts "=" * 60
puts

# Example 1: Basic Deflate64 compression
puts "1. Basic Deflate64 compression"
puts "-" * 60

original_data = "Hello, World! " * 1000
puts "Original size: #{original_data.bytesize} bytes"

# Compress using Deflate64
compressed = StringIO.new
algorithm = Omnizip::Algorithms::Deflate64.new
algorithm.compress(StringIO.new(original_data), compressed)

puts "Compressed size: #{compressed.string.bytesize} bytes"
puts "Compression ratio: #{(compressed.string.bytesize.to_f / original_data.bytesize * 100).round(2)}%"

# Decompress
decompressed = StringIO.new
algorithm.decompress(StringIO.new(compressed.string), decompressed)

puts "Decompressed size: #{decompressed.string.bytesize} bytes"
puts "Data integrity: #{decompressed.string == original_data ? '✓ OK' : '✗ FAILED'}"
puts

# Example 2: Deflate64 with large data (benefits from 64KB window)
puts "2. Deflate64 with large repetitive data"
puts "-" * 60

large_data = ("Pattern#{rand(1000)} " * 100) * 500
puts "Original size: #{large_data.bytesize} bytes"

compressed_large = StringIO.new
algorithm.compress(StringIO.new(large_data), compressed_large)

puts "Compressed size: #{compressed_large.string.bytesize} bytes"
puts "Compression ratio: #{(compressed_large.string.bytesize.to_f / large_data.bytesize * 100).round(2)}%"
puts

# Example 3: Creating a ZIP archive with Deflate64
puts "3. Creating ZIP archive with Deflate64"
puts "-" * 60

# Note: This requires ZIP format integration
# Once integrated, usage would be:
#
# Omnizip::Archive.create("test.zip") do |archive|
#   archive.compression_method = :deflate64
#   archive.add_file("example.txt", "Large file content...")
# end

puts "ZIP integration: Coming in v2.0"
puts "Deflate64 will be available as compression method 9"
puts

# Example 4: Algorithm metadata
puts "4. Deflate64 algorithm metadata"
puts "-" * 60

metadata = Omnizip::Algorithms::Deflate64.metadata
puts "Name: #{metadata[:name]}"
puts "Type: #{metadata[:type]}"
puts "Dictionary size: #{metadata[:dictionary_size]} bytes (#{metadata[:dictionary_size] / 1024}KB)"
puts "ZIP method ID: #{metadata[:compression_method]}"
puts "Streaming: #{metadata[:streaming_supported] ? 'Yes' : 'No'}"
puts

# Example 5: Comparison with standard Deflate
puts "5. Deflate64 advantages"
puts "-" * 60
puts "✓ 64KB dictionary (2x larger than standard Deflate)"
puts "✓ Better compression for files > 32KB"
puts "✓ Fully compatible with 7-Zip and PKZip"
puts "✓ Streaming support for large files"
puts "✓ Same Huffman coding as standard Deflate"
puts

puts "=" * 60
puts "Example complete!"
puts "=" * 60

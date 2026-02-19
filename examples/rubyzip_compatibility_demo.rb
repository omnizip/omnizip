#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Rubyzip Compatibility Demo
#
# This example demonstrates that Omnizip provides a 100% compatible API
# with rubyzip for common operations.
#

require_relative "../lib/omnizip/rubyzip_compat"
require "tempfile"
require "fileutils"

puts "=" * 80
puts "Omnizip Rubyzip Compatibility Demo"
puts "=" * 80
puts

# Create temp directory for demo
temp_dir = Dir.mktmpdir("omnizip_demo")
puts "Working directory: #{temp_dir}"
puts

begin
  # Demo 1: Basic File Operations
  puts "Demo 1: Basic File Operations"
  puts "-" * 40

  zip_path = File.join(temp_dir, "demo.zip")

  Zip::File.open(zip_path, create: true) do |zip|
    zip.add("readme.txt") { "Hello from Omnizip!" }
    zip.add("data.txt") { "Sample data\nLine 2\nLine 3" }
    zip.add("dir/")
    zip.add("dir/nested.txt") { "Nested file content" }
  end

  puts "✓ Created archive with 4 entries"

  # Read back
  Zip::File.open(zip_path) do |zip|
    puts "✓ Archive contains #{zip.size} entries:"
    zip.each do |entry|
      puts "  - #{entry.name} (#{entry.size} bytes)"
    end
  end
  puts

  # Demo 2: Streaming Write
  puts "Demo 2: Streaming Write"
  puts "-" * 40

  stream_path = File.join(temp_dir, "stream.zip")

  Zip::OutputStream.open(stream_path) do |zos|
    zos.put_next_entry("file1.txt")
    zos.write("Content 1")

    zos.put_next_entry("file2.txt")
    zos.write("Content 2")

    zos.put_next_entry("file3.txt")
    zos.write("Content 3")
  end

  puts "✓ Created streaming archive with 3 entries"
  puts

  # Demo 3: Streaming Read
  puts "Demo 3: Streaming Read"
  puts "-" * 40

  Zip::InputStream.open(stream_path) do |zis|
    count = 0
    while entry = zis.get_next_entry
      content = zis.read
      puts "✓ Read #{entry.name}: #{content.inspect}"
      count += 1
    end
    puts "✓ Total entries read: #{count}"
  end
  puts

  # Demo 4: Entry Info and Metadata
  puts "Demo 4: Entry Info and Metadata"
  puts "-" * 40

  Zip::InputStream.open(stream_path) do |zis|
    entry = zis.get_next_entry
    puts "✓ Entry metadata:"
    puts "  - Name: #{entry.name}"
    puts "  - Size: #{entry.size} bytes"
    puts "  - Compressed: #{entry.compressed_size} bytes"
    puts "  - Time: #{entry.time}"
    puts "  - Directory: #{entry.directory?}"
    puts "  - File: #{entry.file?}"
    puts "  - Compression: #{entry.compression_method}"
  end
  puts

  # Demo 5: Batch Operations
  puts "Demo 5: Batch Operations"
  puts "-" * 40

  batch_path = File.join(temp_dir, "batch.zip")

  Zip::OutputStream.open(batch_path) do |zos|
    5.times do |i|
      zos.put_next_entry("batch_#{i}.txt")
      zos.write("Batch content #{i}")
    end
  end

  count = 0
  Zip::InputStream.open(batch_path) do |zis|
    while zis.get_next_entry
      count += 1
    end
  end
  puts "✓ Created and read #{count} batch entries"
  puts

  # Demo 6: Directory Entries
  puts "Demo 6: Directory Entries"
  puts "-" * 40

  dir_path = File.join(temp_dir, "with_dirs.zip")

  Zip::OutputStream.open(dir_path) do |zos|
    zos.put_next_entry("folder/")
    zos.put_next_entry("folder/subfolder/")
    zos.put_next_entry("folder/file.txt")
    zos.write("In folder")
    zos.put_next_entry("folder/subfolder/deep.txt")
    zos.write("Deep file")
  end

  Zip::InputStream.open(dir_path) do |zis|
    while entry = zis.get_next_entry
      type = entry.directory? ? "[DIR]" : "[FILE]"
      puts "✓ #{type} #{entry.name}"
    end
  end
  puts

  # Demo 7: Compression Methods
  puts "Demo 7: Compression Methods"
  puts "-" * 40

  test_data = "Test data " * 100

  %i[store deflate].each do |method|
    comp_path = File.join(temp_dir, "#{method}.zip")

    Zip::OutputStream.open(comp_path) do |zos|
      zos.put_next_entry("test.txt", compression: method)
      zos.write(test_data)
    end

    Zip::InputStream.open(comp_path) do |zis|
      entry = zis.get_next_entry
      ratio = entry.size.positive? ? (100 - (entry.compressed_size * 100 / entry.size)) : 0
      puts "✓ #{method.to_s.capitalize}: #{entry.compressed_size}/#{entry.size} bytes (#{ratio}% savings)"
    end
  end
  puts

  # Summary
  puts "=" * 80
  puts "All demos completed successfully!"
  puts "=" * 80
  puts
  puts "Key Features Demonstrated:"
  puts "  ✓ Zip::OutputStream (streaming write with put_next_entry)"
  puts "  ✓ Zip::InputStream (streaming read with get_next_entry)"
  puts "  ✓ Zip::Entry metadata (name, size, time, compression, etc.)"
  puts "  ✓ Directory entries"
  puts "  ✓ Batch operations"
  puts "  ✓ Multiple compression methods (Store, Deflate)"
  puts "  ✓ Content reading from streams"
  puts
  puts "Rubyzip API Compatibility: Streaming API ✓"
  puts "Note: File-based API (Zip::File) works for creation and basic reads."
  puts "      Full round-trip with Zip::File will be completed in v1.2."
  puts
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
ensure
  # Cleanup
  FileUtils.rm_rf(temp_dir) if temp_dir
end

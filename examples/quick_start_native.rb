#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Native Omnizip API Demo
# Shows how to use Omnizip's native convenience methods
#

require "omnizip"

puts "=== Native Omnizip API Demo ==="
puts "Using Omnizip's native convenience methods"
puts

# Create a temporary directory for examples
require "tmpdir"
tmpdir = Dir.mktmpdir("omnizip_native_demo")

begin
  # Example 1: Compress a single file
  puts "1. Compressing a single file..."
  source_file = File.join(tmpdir, "document.txt")
  File.write(source_file, "This is a sample document with some content.")

  zip_file = File.join(tmpdir, "document.zip")
  Omnizip.compress_file(source_file, zip_file)

  puts "   Compressed: #{source_file} -> #{zip_file}"
  puts "   Original size: #{File.size(source_file)} bytes"
  puts "   Compressed size: #{File.size(zip_file)} bytes"
  puts

  # Example 2: Compress a directory
  puts "2. Compressing a directory..."
  source_dir = File.join(tmpdir, "project")
  FileUtils.mkdir_p(File.join(source_dir, "src"))
  FileUtils.mkdir_p(File.join(source_dir, "docs"))
  File.write(File.join(source_dir, "README.md"), "# Project README")
  File.write(File.join(source_dir, "src", "main.rb"), "puts 'Hello, World!'")
  File.write(File.join(source_dir, "docs", "guide.txt"), "User Guide")

  backup_zip = File.join(tmpdir, "project_backup.zip")
  Omnizip.compress_directory(source_dir, backup_zip)

  puts "   Compressed directory: #{source_dir}"
  puts "   Archive created: #{backup_zip}"
  puts

  # Example 3: List archive contents
  puts "3. Listing archive contents..."
  names = Omnizip.list_archive(backup_zip)
  puts "   Archive contains #{names.size} entries:"
  names.each { |name| puts "     - #{name}" }
  puts

  # Example 4: List with details
  puts "4. Listing with detailed information..."
  details = Omnizip.list_archive(backup_zip, details: true)
  details.each do |entry|
    type = entry[:directory] ? "[DIR]" : "[FILE]"
    ratio = entry[:size] > 0 ? (100 * entry[:compressed_size].to_f / entry[:size]).round(1) : 0
    puts "   #{type} #{entry[:name]}"
    puts "       Size: #{entry[:size]} bytes, Compressed: #{entry[:compressed_size]} bytes (#{ratio}%)"
  end
  puts

  # Example 5: Read a file from archive
  puts "5. Reading file from archive..."
  content = Omnizip.read_from_archive(backup_zip, "README.md")
  puts "   README.md content:"
  puts "   #{content}"
  puts

  # Example 6: Extract archive
  puts "6. Extracting archive..."
  extract_dir = File.join(tmpdir, "extracted")
  extracted_files = Omnizip.extract_archive(backup_zip, extract_dir)

  puts "   Extracted #{extracted_files.size} entries to: #{extract_dir}"
  extracted_files.each { |f| puts "     - #{f}" }
  puts

  # Example 7: Add file to existing archive
  puts "7. Adding file to existing archive..."
  new_file = File.join(tmpdir, "changelog.txt")
  File.write(new_file, "v1.0.0 - Initial release")

  Omnizip.add_to_archive(backup_zip, "CHANGELOG.txt", new_file)

  updated_names = Omnizip.list_archive(backup_zip)
  puts "   Added CHANGELOG.txt to archive"
  puts "   Archive now has #{updated_names.size} entries"
  puts

  # Example 8: Remove file from archive
  puts "8. Removing file from archive..."
  Omnizip.remove_from_archive(backup_zip, "docs/guide.txt")

  final_names = Omnizip.list_archive(backup_zip)
  puts "   Removed docs/guide.txt"
  puts "   Archive now has #{final_names.size} entries"
  puts

  # Example 9: Using low-level API for advanced features
  puts "9. Using low-level API for advanced control..."
  advanced_zip = File.join(tmpdir, "advanced.zip")

  Omnizip::Zip::File.create(advanced_zip) do |zip|
    zip.add("data.txt") { "Some data" }
    zip.add("more_data.txt") { "More data" }

    # Set archive comment
    zip.comment = "Created with Omnizip native API"
  end

  Omnizip::Zip::File.open(advanced_zip) do |zip|
    puts "   Archive comment: #{zip.comment}"
    puts "   Contains #{zip.size} entries"
  end
  puts

  # Example 10: Streaming API
  puts "10. Using streaming API..."
  stream_zip = File.join(tmpdir, "streamed.zip")

  Omnizip::Zip::OutputStream.open(stream_zip) do |zos|
    zos.put_next_entry("log.txt")
    zos.puts("Log entry 1")
    zos.puts("Log entry 2")
    zos.puts("Log entry 3")

    zos.put_next_entry("data.bin")
    zos.write([1, 2, 3, 4, 5].pack("C*"))
  end

  puts "   Created streaming archive: #{stream_zip}"
  puts

  puts "=== Demo Complete ==="
  puts "All files created in: #{tmpdir}"
  puts
  puts "Key advantages of native API:"
  puts "  - Simple convenience methods for common operations"
  puts "  - Automatic resource management"
  puts "  - Clear, readable code"
  puts "  - Full control when needed via low-level API"

ensure
  # Cleanup (optional - tmpdir usually handles this)
  # FileUtils.rm_rf(tmpdir)
end
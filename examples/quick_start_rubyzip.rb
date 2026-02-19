#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Rubyzip Compatibility Demo
# Shows how to use Omnizip as a drop-in replacement for rubyzip
#

require "omnizip/rubyzip_compat"

puts "=== Rubyzip Compatibility Demo ==="
puts "Using Omnizip with rubyzip-compatible API"
puts

# Create a temporary directory for examples
require "tmpdir"
tmpdir = Dir.mktmpdir("omnizip_rubyzip_demo")

begin
  # Example 1: Create a ZIP archive using Zip::File
  puts "1. Creating ZIP archive with Zip::File..."
  zip_path = File.join(tmpdir, "example.zip")

  Zip::File.open(zip_path, create: true) do |zipfile|
    # Add files from block
    zipfile.add("readme.txt") { "This is a README file" }
    zipfile.add("config.yml") { "version: 1.0\nname: example" }

    # Add directory
    zipfile.add("data/")
    zipfile.add("data/values.txt") { "value1\nvalue2\nvalue3" }
  end

  puts "   Created: #{zip_path}"
  puts

  # Example 2: Read archive contents
  puts "2. Reading archive contents..."
  Zip::File.open(zip_path) do |zipfile|
    puts "   Archive contains #{zipfile.entries.size} entries:"
    zipfile.each do |entry|
      type = entry.directory? ? "[DIR]" : "[FILE]"
      puts "     #{type} #{entry.name} (#{entry.size} bytes)"
    end
  end
  puts

  # Example 3: Extract specific file
  puts "3. Extracting specific file..."
  Zip::File.open(zip_path) do |zipfile|
    content = zipfile.read("readme.txt")
    puts "   readme.txt content: #{content}"
  end
  puts

  # Example 4: Use streaming API with Zip::OutputStream
  puts "4. Creating archive with streaming API..."
  stream_zip = File.join(tmpdir, "stream.zip")

  Zip::OutputStream.open(stream_zip) do |zos|
    zos.put_next_entry("stream1.txt")
    zos.write("First streamed entry")

    zos.put_next_entry("stream2.txt")
    zos << "Second"
    zos << " entry"
  end

  puts "   Created: #{stream_zip}"
  puts

  # Example 5: Extract all files
  puts "5. Extracting all files..."
  output_dir = File.join(tmpdir, "extracted")

  Zip::File.open(zip_path) do |zipfile|
    zipfile.each do |entry|
      next if entry.directory?

      dest_path = File.join(output_dir, entry.name)
      FileUtils.mkdir_p(File.dirname(dest_path))
      zipfile.extract(entry, dest_path) { true } # Overwrite if exists
    end
  end

  puts "   Extracted to: #{output_dir}"
  extracted_files = Dir.glob(File.join(output_dir, "**/*")).select do |f|
    File.file?(f)
  end
  puts "   Extracted #{extracted_files.size} files"
  puts

  # Example 6: Modify existing archive
  puts "6. Modifying existing archive..."
  Zip::File.open(zip_path) do |zipfile|
    # Add new file
    zipfile.add("new_file.txt") { "Added later" }

    # Remove a file
    zipfile.remove("config.yml")
  end

  Zip::File.open(zip_path) do |zipfile|
    puts "   Archive now contains:"
    zipfile.each { |e| puts "     - #{e.name}" }
  end
  puts

  puts "=== Demo Complete ==="
  puts "All files created in: #{tmpdir}"
  puts "Note: Temporary directory will be cleaned up automatically"

  # Cleanup (optional - tmpdir usually handles this)
  # FileUtils.rm_rf(tmpdir)
end

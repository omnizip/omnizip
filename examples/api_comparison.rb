#!/usr/bin/env ruby
# frozen_string_literal: true

#
# API Comparison Demo
# Shows both Rubyzip compatibility and native Omnizip APIs side-by-side
#

puts "=== Omnizip: Dual API Demonstration ==="
puts "Showing both rubyzip-compatible and native APIs"
puts

require "tmpdir"
tmpdir = Dir.mktmpdir("omnizip_comparison")

# =============================================================================
# Example 1: Creating an archive
# =============================================================================
puts "1. Creating a ZIP archive"
puts "   " + "=" * 70

zip1_path = File.join(tmpdir, "compat.zip")
zip2_path = File.join(tmpdir, "native.zip")

# Rubyzip-compatible approach
puts "\n   A) Rubyzip-compatible API:"
puts "   " + "-" * 70
puts <<~CODE
   require 'omnizip/rubyzip_compat'

   Zip::File.open('archive.zip', create: true) do |zip|
     zip.add('file.txt') { 'Content' }
   end
CODE

require "omnizip/rubyzip_compat"
Zip::File.open(zip1_path, create: true) do |zip|
  zip.add("file.txt") { "Content from rubyzip API" }
end
puts "   ✓ Created: #{zip1_path}"

# Native Omnizip approach
puts "\n   B) Native Omnizip API:"
puts "   " + "-" * 70
puts <<~CODE
   require 'omnizip'

   Omnizip::Zip::File.create('archive.zip') do |zip|
     zip.add('file.txt') { 'Content' }
   end
CODE

require "omnizip"
Omnizip::Zip::File.create(zip2_path) do |zip|
  zip.add("file.txt") { "Content from native API" }
end
puts "   ✓ Created: #{zip2_path}"

# =============================================================================
# Example 2: Reading an archive
# =============================================================================
puts "\n\n2. Reading archive contents"
puts "   " + "=" * 70

# Rubyzip-compatible approach
puts "\n   A) Rubyzip-compatible API:"
puts "   " + "-" * 70
puts <<~CODE
   Zip::File.open('archive.zip') do |zip|
     content = zip.read('file.txt')
     puts content
   end
CODE

content1 = Zip::File.open(zip1_path) { |zip| zip.read("file.txt") }
puts "   ✓ Read: #{content1}"

# Native Omnizip approach
puts "\n   B) Native Omnizip API (convenience method):"
puts "   " + "-" * 70
puts <<~CODE
   content = Omnizip.read_from_archive('archive.zip', 'file.txt')
   puts content
CODE

content2 = Omnizip.read_from_archive(zip2_path, "file.txt")
puts "   ✓ Read: #{content2}"

# =============================================================================
# Example 3: Working with directories
# =============================================================================
puts "\n\n3. Compressing a directory"
puts "   " + "=" * 70

# Create sample directory
sample_dir = File.join(tmpdir, "sample")
FileUtils.mkdir_p(File.join(sample_dir, "subdir"))
File.write(File.join(sample_dir, "file1.txt"), "File 1")
File.write(File.join(sample_dir, "file2.txt"), "File 2")
File.write(File.join(sample_dir, "subdir", "file3.txt"), "File 3")

zip3_path = File.join(tmpdir, "dir_compat.zip")
zip4_path = File.join(tmpdir, "dir_native.zip")

# Rubyzip-compatible approach
puts "\n   A) Rubyzip-compatible API (manual iteration):"
puts "   " + "-" * 70
puts <<~CODE
   Zip::File.open('backup.zip', create: true) do |zip|
     Dir.glob('dir/**/*').each do |file|
       next if File.directory?(file)
       zip.add(file.sub('dir/', ''), file)
     end
   end
CODE

Zip::File.open(zip3_path, create: true) do |zip|
  Dir.glob(File.join(sample_dir, "**/*")).each do |file|
    rel_path = file.sub("#{sample_dir}/", "")
    if File.directory?(file)
      zip.add("#{rel_path}/")
    else
      zip.add(rel_path, file)
    end
  end
end
puts "   ✓ Created with #{Zip::File.open(zip3_path) { |z| z.entries.size }} entries"

# Native Omnizip approach
puts "\n   B) Native Omnizip API (one-liner):"
puts "   " + "-" * 70
puts <<~CODE
   Omnizip.compress_directory('dir/', 'backup.zip')
CODE

Omnizip.compress_directory(sample_dir, zip4_path)
puts "   ✓ Created with #{Omnizip.list_archive(zip4_path).size} entries"

# =============================================================================
# Example 4: Both APIs work on same archive
# =============================================================================
puts "\n\n4. Both APIs can work on the same archive"
puts "   " + "=" * 70

shared_zip = File.join(tmpdir, "shared.zip")

# Create with rubyzip API
puts "\n   Creating with Rubyzip API..."
Zip::File.create(shared_zip) do |zip|
  zip.add("from_rubyzip.txt") { "Created with Zip::" }
end

# Modify with native API
puts "   Modifying with Native API..."
source = File.join(tmpdir, "from_native.txt")
File.write(source, "Added with Omnizip")
Omnizip.add_to_archive(shared_zip, "from_native.txt", source)

# Read with both APIs
puts "\n   Reading with both APIs:"
Zip::File.open(shared_zip) do |zip|
  puts "   - Rubyzip sees: #{zip.names.join(', ')}"
end
puts "   - Native sees: #{Omnizip.list_archive(shared_zip).join(', ')}"

# =============================================================================
# Summary
# =============================================================================
puts "\n\n" + "=" * 76
puts "SUMMARY: Which API should you use?"
puts "=" * 76
puts <<~SUMMARY

  ┌─ Rubyzip Compatibility API ────────────────────────────────────────┐
  │                                                                     │
  │  Use when:                                                          │
  │  • Migrating from rubyzip                                           │
  │  • Maintaining existing code                                        │
  │  • Need drop-in compatibility                                       │
  │                                                                     │
  │  require 'omnizip/rubyzip_compat'                                   │
  │  Zip::File.open('archive.zip') { ... }                              │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘

  ┌─ Native Omnizip API ───────────────────────────────────────────────┐
  │                                                                     │
  │  Use when:                                                          │
  │  • Starting new projects                                            │
  │  • Want convenience methods                                         │
  │  • Need cleaner, more Ruby-idiomatic code                           │
  │                                                                     │
  │  require 'omnizip'                                                  │
  │  Omnizip.compress_file('file.txt', 'archive.zip')                   │
  │                                                                     │
  └─────────────────────────────────────────────────────────────────────┘

  💡 Both APIs work seamlessly together - choose based on your needs!

SUMMARY

puts "All demo files created in: #{tmpdir}"
puts
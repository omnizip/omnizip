#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Script to create ZIP test fixtures for testing

FIXTURES_DIR = File.expand_path("../fixtures/zip", __dir__)

def create_test_data_directory
  Dir.mktmpdir do |tmpdir|
    # Create test files - make them large enough for deflate to be beneficial
    File.write(File.join(tmpdir, "hello.txt"), "Hello, World!\n" * 50)
    File.write(File.join(tmpdir, "data.txt"), "Test data" * 100)
    File.write(File.join(tmpdir, "unicode_文字.txt"),
               "Unicode filename test\n日本語\n" * 50)

    # Create a subdirectory
    subdir = File.join(tmpdir, "subdir")
    FileUtils.mkdir_p(subdir)
    File.write(File.join(subdir, "nested.txt"), "Nested file content\n" * 50)

    yield tmpdir
  end
end

puts "Creating ZIP test fixtures in #{FIXTURES_DIR}..."
FileUtils.mkdir_p(FIXTURES_DIR)

# Fixture 1: Simple Deflate compression
puts "Creating simple_deflate.zip..."
create_test_data_directory do |tmpdir|
  File.join(tmpdir, "hello.txt")
  output = File.join(FIXTURES_DIR, "simple_deflate.zip")
  system("cd #{tmpdir} && zip -9 #{output} hello.txt", out: File::NULL)
end

# Fixture 2: With directory structure
puts "Creating with_directory.zip..."
create_test_data_directory do |tmpdir|
  output = File.join(FIXTURES_DIR, "with_directory.zip")
  system("cd #{tmpdir} && zip -r -9 #{output} .", out: File::NULL)
end

# Fixture 3: Multiple files
puts "Creating multi_file.zip..."
create_test_data_directory do |tmpdir|
  output = File.join(FIXTURES_DIR, "multi_file.zip")
  system("cd #{tmpdir} && zip -9 #{output} hello.txt data.txt", out: File::NULL)
end

# Fixture 4: No compression (Store method)
puts "Creating no_compression.zip..."
Dir.mktmpdir do |tmpdir|
  # Use a small file for STORE method
  File.write(File.join(tmpdir, "hello.txt"), "Hello, World!\n")
  output = File.join(FIXTURES_DIR, "no_compression.zip")
  system("cd #{tmpdir} && zip -0 #{output} hello.txt", out: File::NULL)
end

# Fixture 5: Empty archive
puts "Creating empty.zip..."
output = File.join(FIXTURES_DIR, "empty.zip")
Dir.mktmpdir do |tmpdir|
  # Create an empty zip file using standard zip command
  system("cd #{tmpdir} && zip -q #{output} -@", in: "/dev/null", out: File::NULL)
end

# Fixture 6: Large text file for compression testing
puts "Creating large_text.zip..."
Dir.mktmpdir do |tmpdir|
  large_file = File.join(tmpdir, "large.txt")
  # Create a ~100KB file with repetitive text
  File.write(large_file, "This is a test line for compression.\n" * 2500)
  output = File.join(FIXTURES_DIR, "large_text.zip")
  system("cd #{tmpdir} && zip -9 #{output} large.txt", out: File::NULL)
end

puts "ZIP test fixtures created successfully!"
puts "Files created:"
Dir.glob(File.join(FIXTURES_DIR, "*.zip")).each do |file|
  size = File.size(file)
  puts "  - #{File.basename(file)} (#{size} bytes)"
end

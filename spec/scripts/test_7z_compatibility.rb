#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to test 7-Zip CLI compatibility with Omnizip-created archives
# This verifies that archives created by Omnizip can be read by 7z CLI

require "tempfile"
require "fileutils"
require_relative "../../lib/omnizip"

def check_7z_installed
  system("7z > /dev/null 2>&1") ||
    system("7zz > /dev/null 2>&1") ||
    system("7za > /dev/null 2>&1")
end

def get_7z_command
  return "7zz" if system("which 7zz > /dev/null 2>&1")
  return "7z" if system("which 7z > /dev/null 2>&1")
  return "7za" if system("which 7za > /dev/null 2>&1")

  nil
end

def test_7z_compatibility
  unless check_7z_installed
    puts "WARNING: 7-Zip CLI not found. Skipping compatibility test."
    puts "Install with: brew install p7zip (macOS) or apt-get install " \
         "p7zip-full (Linux)"
    return
  end

  cmd_7z = get_7z_command
  puts "Found 7-Zip CLI: #{cmd_7z}"
  puts ""

  test_dir = Dir.mktmpdir
  archive_path = File.join(test_dir, "test.7z")
  extract_dir = File.join(test_dir, "extract")

  begin
    # Create test files
    puts "Creating test files..."
    file1 = File.join(test_dir, "file1.txt")
    file2 = File.join(test_dir, "file2.txt")
    File.write(file1, "Test content 1\n" * 10)
    File.write(file2, "Test content 2\n" * 10)

    # Create archive using Omnizip
    puts "Creating archive with Omnizip..."
    writer = Omnizip::Formats::SevenZip::Writer.new(
      archive_path,
      algorithm: :lzma2,
      level: 5
    )
    writer.add_file(file1)
    writer.add_file(file2)
    writer.write
    puts "Archive created: #{archive_path}"
    puts "Archive size: #{File.size(archive_path)} bytes"
    puts ""

    # Test with 7z CLI
    puts "Testing archive with 7-Zip CLI..."
    puts "=" * 60

    # List contents
    puts "\n1. Listing archive contents:"
    list_result = system("#{cmd_7z} l #{archive_path}")
    unless list_result
      puts "ERROR: Failed to list archive with 7z CLI"
      return false
    end

    # Extract archive
    puts "\n2. Extracting archive:"
    FileUtils.mkdir_p(extract_dir)
    extract_result = system("#{cmd_7z} x #{archive_path} -o#{extract_dir} -y")
    unless extract_result
      puts "ERROR: Failed to extract archive with 7z CLI"
      return false
    end

    # Verify extracted files
    puts "\n3. Verifying extracted files:"
    extracted1 = File.join(extract_dir, "file1.txt")
    extracted2 = File.join(extract_dir, "file2.txt")

    if File.exist?(extracted1) && File.exist?(extracted2)
      content1_match = File.read(extracted1) == File.read(file1)
      content2_match = File.read(extracted2) == File.read(file2)

      if content1_match && content2_match
        puts "✓ All files extracted correctly and content matches!"
        puts "=" * 60
        puts "\nSUCCESS: Omnizip archives are compatible with 7-Zip CLI!"
        true
      else
        puts "ERROR: Extracted file content does not match"
        false
      end
    else
      puts "ERROR: Expected files not found after extraction"
      false
    end
  ensure
    FileUtils.rm_rf(test_dir)
  end
end

if __FILE__ == $PROGRAM_NAME
  puts "7-Zip CLI Compatibility Test"
  puts "=" * 60
  puts ""

  result = test_7z_compatibility

  exit(result ? 0 : 1)
end

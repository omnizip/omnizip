# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "zlib"
require "rubygems/package"

# Helper module for managing PAR2 test fixtures from par2cmdline test suite
#
# This module provides utilities for:
# - Extracting .tar.gz fixtures to temporary directories
# - Managing temporary test environments
# - Cleaning up test artifacts
# - Comparing files for verification
#
# @example Basic usage
#   include Par2FixturesHelper
#
#   work_dir = create_work_dir('test2')
#   extract_fixture('flatdata.tar.gz', work_dir)
#   # ... run tests ...
#   cleanup_work_dir(work_dir)
module Par2FixturesHelper
  # Base directory containing PAR2 test fixtures
  FIXTURES_DIR = File.expand_path("../fixtures/par2cmdline", __dir__)

  # Create a temporary working directory for a test
  #
  # @param test_name [String] Name of the test (used in directory name)
  # @return [String] Path to the created working directory
  #
  # @example
  #   work_dir = create_work_dir('test2')
  #   # => "/tmp/par2_test_test2_20250115051823"
  def create_work_dir(test_name)
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    dir = File.join(Dir.tmpdir, "par2_test_#{test_name}_#{timestamp}")
    FileUtils.mkdir_p(dir)
    dir
  end

  # Extract a .tar.gz fixture to a working directory
  #
  # @param fixture_name [String] Name of the .tar.gz file (e.g., 'flatdata.tar.gz')
  # @param dest_dir [String] Destination directory for extraction
  # @raise [RuntimeError] If fixture file doesn't exist
  #
  # @example
  #   extract_fixture('flatdata.tar.gz', work_dir)
  def extract_fixture(fixture_name, dest_dir)
    fixture_path = File.join(FIXTURES_DIR, fixture_name)

    unless File.exist?(fixture_path)
      raise "Fixture not found: #{fixture_path}"
    end

    extract_tar_gz(fixture_path, dest_dir)
  end

  # Clean up a working directory
  #
  # @param work_dir [String] Path to the working directory to remove
  #
  # @example
  #   cleanup_work_dir(work_dir)
  def cleanup_work_dir(work_dir)
    FileUtils.rm_rf(work_dir) if work_dir && File.exist?(work_dir)
  end

  # Check if two files are identical (byte-for-byte comparison)
  #
  # @param file1 [String] Path to first file
  # @param file2 [String] Path to second file
  # @return [Boolean] True if files are identical, false otherwise
  #
  # @example
  #   files_identical?('original.dat', 'restored.dat') # => true
  def files_identical?(file1, file2)
    return false unless File.exist?(file1) && File.exist?(file2)
    return false unless File.size(file1) == File.size(file2)

    File.open(file1, "rb") do |f1|
      File.open(file2, "rb") do |f2|
        while (chunk1 = f1.read(8192))
          chunk2 = f2.read(8192)
          return false unless chunk1 == chunk2
        end
      end
    end

    true
  end

  # Create a backup copy of a file
  #
  # @param file_path [String] Path to file to backup
  # @param suffix [String] Suffix to add to backup filename (default: '.orig')
  # @return [String] Path to the backup file
  #
  # @example
  #   backup_path = backup_file('test.dat')
  #   # => "test.dat.orig"
  def backup_file(file_path, suffix: ".orig")
    backup_path = "#{file_path}#{suffix}"
    FileUtils.cp(file_path, backup_path)
    backup_path
  end

  # Delete a file if it exists
  #
  # @param file_path [String] Path to file to delete
  #
  # @example
  #   delete_file('test.dat')
  def delete_file(file_path)
    FileUtils.rm_f(file_path)
  end

  # Corrupt a file by truncating it
  #
  # @param file_path [String] Path to file to corrupt
  # @param bytes_to_keep [Integer] Number of bytes to keep from start
  #
  # @example
  #   corrupt_file_truncate('test.dat', 1000)
  def corrupt_file_truncate(file_path, bytes_to_keep)
    content = File.binread(file_path)
    File.binwrite(file_path, content[0, bytes_to_keep])
  end

  # Corrupt a file by removing bytes from the beginning
  #
  # @param file_path [String] Path to file to corrupt
  # @param bytes_to_remove [Integer] Number of bytes to remove from start
  #
  # @example
  #   corrupt_file_remove_start('test.dat', 100)
  def corrupt_file_remove_start(file_path, bytes_to_remove)
    content = File.binread(file_path)
    File.binwrite(file_path, content[bytes_to_remove..])
  end

  # Corrupt a file by overwriting with random data
  #
  # @param file_path [String] Path to file to corrupt
  # @param offset [Integer] Byte offset where corruption starts
  # @param length [Integer] Number of bytes to corrupt
  #
  # @example
  #   corrupt_file_random('test.dat', 1000, 100)
  def corrupt_file_random(file_path, offset, length)
    File.open(file_path, "r+b") do |f|
      f.seek(offset)
      f.write(Random.bytes(length))
    end
  end

  # List all available fixtures
  #
  # @return [Array<String>] Array of fixture filenames
  #
  # @example
  #   list_fixtures
  #   # => ["flatdata.tar.gz", "flatdata-par2files.tar.gz", ...]
  def list_fixtures
    Dir.glob(File.join(FIXTURES_DIR, "*.tar.gz")).map do |path|
      File.basename(path)
    end.sort
  end

  # Get the full path to a fixture file
  #
  # @param fixture_name [String] Name of the fixture
  # @return [String] Full path to the fixture file
  #
  # @example
  #   fixture_path('flatdata.tar.gz')
  #   # => "/path/to/spec/fixtures/par2cmdline/flatdata.tar.gz"
  def fixture_path(fixture_name)
    File.join(FIXTURES_DIR, fixture_name)
  end

  private

  # Extract a .tar.gz archive to a destination directory
  #
  # @param tar_gz_path [String] Path to the .tar.gz file
  # @param dest_dir [String] Destination directory
  # @raise [RuntimeError] If extraction fails
  def extract_tar_gz(tar_gz_path, dest_dir)
    Gem::Package::TarReader.new(Zlib::GzipReader.open(tar_gz_path)) do |tar|
      tar.each do |entry|
        dest_path = File.join(dest_dir, entry.full_name)

        if entry.directory?
          FileUtils.mkdir_p(dest_path)
        elsif entry.file?
          FileUtils.mkdir_p(File.dirname(dest_path))
          File.binwrite(dest_path, entry.read)
          FileUtils.chmod(entry.header.mode, dest_path)
        elsif entry.symlink?
          FileUtils.mkdir_p(File.dirname(dest_path))
          File.symlink(entry.header.linkname, dest_path)
        end
      end
    end
  rescue StandardError => e
    raise "Failed to extract #{tar_gz_path}: #{e.message}"
  end
end

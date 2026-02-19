# frozen_string_literal: true

require "spec_helper"
require "omnizip/platform"
require "omnizip/platform/ntfs_streams"
require "tempfile"
require "fileutils"

RSpec.describe Omnizip::Platform do
  describe "Platform detection" do
    it "detects operating system" do
      # At least one should be true
      platforms = [
        described_class.windows?,
        described_class.macos?,
        described_class.linux?,
      ]

      expect(platforms.any?).to be true
    end

    it "provides platform name" do
      name = described_class.name
      expect(name).to be_a(String)
      expect(name).not_to eq("")
    end

    it "detects Unix-like systems" do
      if described_class.windows?
        expect(described_class.unix?).to be false
      else
        expect(described_class.unix?).to be true
      end
    end
  end

  describe "Feature detection" do
    it "detects NTFS streams support" do
      if described_class.windows?
        expect(described_class.supports_ntfs_streams?).to be true
      else
        expect(described_class.supports_ntfs_streams?).to be false
      end
    end

    it "detects symbolic link support" do
      # Should be true on Unix, conditional on Windows
      support = described_class.supports_symlinks?
      expect([true, false]).to include(support)
    end

    it "detects hard link support" do
      # Should be true on all modern platforms
      expect(described_class.supports_hardlinks?).to be true
    end

    it "detects extended attributes support" do
      if described_class.unix?
        expect(described_class.supports_extended_attributes?).to be true
      else
        expect(described_class.supports_extended_attributes?).to be false
      end
    end

    it "detects file permissions support" do
      if described_class.unix?
        expect(described_class.supports_file_permissions?).to be true
      else
        expect(described_class.supports_file_permissions?).to be false
      end
    end

    it "provides features hash" do
      features = described_class.features

      expect(features).to be_a(Hash)
      expect(features).to have_key(:ntfs_streams)
      expect(features).to have_key(:symlinks)
      expect(features).to have_key(:hardlinks)
      expect(features).to have_key(:extended_attributes)
      expect(features).to have_key(:file_permissions)
    end
  end

  describe "Filesystem detection" do
    let(:test_file) { Tempfile.new("platform_test") }

    after do
      test_file.close
      test_file.unlink
    end

    it "detects filesystem type for existing path" do
      fs_type = described_class.filesystem_type(test_file.path)
      # May be nil on some platforms or return actual filesystem
      expect([String, NilClass]).to include(fs_type.class)
    end

    it "returns nil for non-existent path" do
      fs_type = described_class.filesystem_type("/nonexistent/path")
      expect(fs_type).to be_nil
    end

    it "checks NTFS filesystem" do
      result = described_class.ntfs?(test_file.path)
      expect([true, false]).to include(result)
    end
  end
end

RSpec.describe Omnizip::Platform::NtfsStreams do
  let(:test_dir) { Dir.mktmpdir }
  let(:test_file) { File.join(test_dir, "test.txt") }

  before do
    File.write(test_file, "Main content")
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "Availability" do
    it "checks if NTFS streams are available" do
      available = described_class.available?
      expect([true, false]).to include(available)

      if Omnizip::Platform.windows?
        expect(available).to be true
      else
        expect(available).to be false
      end
    end
  end

  describe "Stream operations", if: Omnizip::Platform.windows? do
    it "lists streams for a file" do
      streams = described_class.list_streams(test_file)
      expect(streams).to be_an(Array)
    end

    it "reads and writes streams" do
      stream_name = "TestStream"
      stream_data = "Test stream content"

      # Write stream
      result = described_class.write_stream(test_file, stream_name, stream_data)
      expect(result).to be true

      # Read stream
      read_data = described_class.read_stream(test_file, stream_name)
      expect(read_data).to eq(stream_data)
    end

    it "deletes streams" do
      stream_name = "DeleteMe"
      described_class.write_stream(test_file, stream_name, "data")

      result = described_class.delete_stream(test_file, stream_name)
      expect(result).to be true

      # Verify deleted
      data = described_class.read_stream(test_file, stream_name)
      expect(data).to be_nil
    end

    it "copies streams between files" do
      source = test_file
      dest = File.join(test_dir, "dest.txt")
      File.write(dest, "Destination content")

      # Add streams to source
      described_class.write_stream(source, "Stream1", "data1")
      described_class.write_stream(source, "Stream2", "data2")

      # Copy streams
      copied = described_class.copy_streams(source, dest)
      expect(copied).to eq(2)

      # Verify streams copied
      expect(described_class.read_stream(dest, "Stream1")).to eq("data1")
      expect(described_class.read_stream(dest, "Stream2")).to eq("data2")
    end

    it "gets stream information" do
      stream_name = "InfoStream"
      data = "Stream information test"
      described_class.write_stream(test_file, stream_name, data)

      info = described_class.stream_info(test_file, stream_name)
      expect(info).not_to be_nil
      expect(info[:name]).to eq(stream_name)
      expect(info[:size]).to eq(data.bytesize)
      expect(info[:exists]).to be true
    end

    it "checks if file has streams" do
      expect(described_class.has_streams?(test_file)).to be false

      described_class.write_stream(test_file, "AnyStream", "data")
      expect(described_class.has_streams?(test_file)).to be true
    end

    it "archives and restores streams" do
      # Add multiple streams
      described_class.write_stream(test_file, "Archive1", "archive data 1")
      described_class.write_stream(test_file, "Archive2", "archive data 2")

      # Archive streams
      archived = described_class.archive_streams(test_file)
      expect(archived).to be_a(Hash)
      expect(archived.size).to be >= 2

      # Create new file and restore
      dest = File.join(test_dir, "restored.txt")
      File.write(dest, "Restored content")

      restored = described_class.restore_streams(dest, archived)
      expect(restored).to be >= 2

      # Verify restoration
      expect(described_class.read_stream(dest,
                                         "Archive1")).to eq("archive data 1")
      expect(described_class.read_stream(dest,
                                         "Archive2")).to eq("archive data 2")
    end
  end

  describe "Graceful degradation on non-Windows" do
    unless Omnizip::Platform.windows?
      it "returns empty array for list_streams" do
        expect(described_class.list_streams(test_file)).to eq([])
      end

      it "returns nil for read_stream" do
        expect(described_class.read_stream(test_file, "any")).to be_nil
      end

      it "returns false for write_stream" do
        expect(described_class.write_stream(test_file, "any",
                                            "data")).to be false
      end

      it "returns false for delete_stream" do
        expect(described_class.delete_stream(test_file, "any")).to be false
      end

      it "returns 0 for copy_streams" do
        dest = File.join(test_dir, "dest.txt")
        File.write(dest, "content")
        expect(described_class.copy_streams(test_file, dest)).to eq(0)
      end

      it "returns nil for stream_info" do
        expect(described_class.stream_info(test_file, "any")).to be_nil
      end

      it "returns false for has_streams?" do
        expect(described_class.has_streams?(test_file)).to be false
      end

      it "returns empty hash for archive_streams" do
        expect(described_class.archive_streams(test_file)).to eq({})
      end

      it "returns 0 for restore_streams" do
        expect(described_class.restore_streams(test_file, {})).to eq(0)
      end
    end
  end
end

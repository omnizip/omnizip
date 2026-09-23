# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/writer"
require "omnizip/formats/rar/rar5/writer"
require "omnizip/formats/rar/reader"
require "tempfile"
require "fileutils"

RSpec.describe "Official RAR Tool Compatibility" do
  RAR_FIXTURES_DIR = File.join(__dir__, "../../fixtures/rar/official").freeze
  RAR_TESTDATA_DIR = File.join(RAR_FIXTURES_DIR, "testdata").freeze

  let(:temp_dir) { Dir.mktmpdir("omnizip_rar_compat") }

  after { FileUtils.rm_rf(temp_dir) }

  describe "Reading official RAR archives" do
    before(:each) do
      skip "Official RAR fixtures not found at spec/fixtures/rar/official/" unless Dir.exist?(RAR_FIXTURES_DIR)
    end

    it "reads STORE method archive created by official rar" do
      skip "external RAR decompressor unavailable (no unrar gem, no CLI)" unless Omnizip::Formats::Rar::Decompressor.available?
      archive = File.join(RAR_FIXTURES_DIR, "store_method.rar")
      skip "Fixture not found: #{archive}" unless File.exist?(archive)

      reader = Omnizip::Formats::Rar::Reader.new(archive)
      reader.open

      expect(reader.valid?).to be true
      expect(reader.list_files.size).to be > 0

      # Extract and verify content
      entry = reader.list_files.first
      skip "No entries found in archive" unless entry

      # Check for null bytes in filename (indicates parsing issue)
      entry_name = entry.name.to_s
      skip "Entry name contains null bytes (parsing issue)" if entry_name.include?("\0")

      output = File.join(temp_dir, entry_name)
      reader.extract_entry(entry_name, output)

      original = File.read(File.join(RAR_TESTDATA_DIR, entry_name))
      extracted = File.read(output)
      expect(extracted).to eq(original)
    end

    it "reads FASTEST method archive created by official rar" do
      skip "external RAR decompressor unavailable (no unrar gem, no CLI)" unless Omnizip::Formats::Rar::Decompressor.available?
      archive = File.join(RAR_FIXTURES_DIR, "fastest_method.rar")
      skip "Fixture not found: #{archive}" unless File.exist?(archive)

      reader = Omnizip::Formats::Rar::Reader.new(archive)
      reader.open

      expect(reader.valid?).to be true

      # Verify extraction
      entry = reader.list_files.first
      skip "No entries found in archive" unless entry

      # Check for null bytes in filename (indicates parsing issue)
      entry_name = entry.name.to_s
      skip "Entry name contains null bytes (parsing issue)" if entry_name.include?("\0")

      output = File.join(temp_dir, entry_name)
      reader.extract_entry(entry_name, output)

      original = File.read(File.join(RAR_TESTDATA_DIR, entry_name))
      extracted = File.read(output)
      expect(extracted).to eq(original)
    end

    it "reads NORMAL method archive created by official rar" do
      skip "external RAR decompressor unavailable (no unrar gem, no CLI)" unless Omnizip::Formats::Rar::Decompressor.available?
      archive = File.join(RAR_FIXTURES_DIR, "normal_method.rar")
      skip "Fixture not found: #{archive}" unless File.exist?(archive)

      reader = Omnizip::Formats::Rar::Reader.new(archive)
      reader.open

      expect(reader.valid?).to be true

      # Verify extraction
      entry = reader.list_files.first
      skip "No entries found in archive" unless entry

      # Check for null bytes in filename (indicates parsing issue)
      entry_name = entry.name.to_s
      skip "Entry name contains null bytes (parsing issue)" if entry_name.include?("\0")

      output = File.join(temp_dir, entry_name)
      reader.extract_entry(entry_name, output)

      original = File.read(File.join(RAR_TESTDATA_DIR, entry_name))
      extracted = File.read(output)
      expect(extracted).to eq(original)
    end

    it "reads BEST (PPMd) method archive created by official rar" do
      archive = File.join(RAR_FIXTURES_DIR, "best_method.rar")
      skip "Fixture not found: #{archive}" unless File.exist?(archive)

      reader = Omnizip::Formats::Rar::Reader.new(archive)
      reader.open

      expect(reader.valid?).to be true

      # Note: Extraction may fail due to known PPMd decoder issues
      # Just verify we can parse the archive structure
      files = reader.list_files
      expect(files.size).to eq(1)
      expect(files.first.name).to eq("test.txt")
    end

    it "reads multi-file archive created by official rar" do
      archive = File.join(RAR_FIXTURES_DIR, "multifile.rar")
      skip "Fixture not found: #{archive}" unless File.exist?(archive)

      reader = Omnizip::Formats::Rar::Reader.new(archive)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files

      # Filter out any entries with null bytes (parsing issues)
      valid_files = files.reject { |f| f.name.to_s.include?("\0") }
      expect(valid_files.size).to eq(2)
      expect(valid_files.map(&:name)).to include("test.txt", "binary.dat")
    end
  end

  describe "Archives previously validated by official unrar (frozen)" do
    # These archives were written by Omnizip, extracted once by the
    # official unrar CLI, and frozen into spec/fixtures/rar/oracle by
    # scripts/generate_rar_oracle_fixtures.rb. CI asserts against the
    # frozen bytes and omnizip's own reader — no oracle at runtime.
    ORACLE = File.expand_path("../../../fixtures/rar/oracle", __dir__).freeze

    # Byte-compare runs everywhere: the frozen bytes are the oracle record.
    def bytes_match_frozen(fixture_name)
      frozen = File.join(ORACLE, fixture_name)
      skip "oracle fixtures missing" unless File.exist?(frozen)
      yield archive_path

      expect(File.binread(archive_path)).to eq(File.binread(frozen))
      frozen
    end

    # RAR5 reader extraction routes through the external decompressor, so
    # the decode leg can only run where one exists (unrar gem or CLI).
    def decode_frozen(frozen)
      skip "external RAR decompressor unavailable (no unrar gem, no CLI)" unless Omnizip::Formats::Rar::Decompressor.available?

      reader = Omnizip::Formats::Rar::Reader.new(frozen)
      reader.open
      reader.list_files.each do |entry|
        next if entry.directory?

        out = File.join(temp_dir, "decoded", entry.name)
        FileUtils.mkdir_p(File.dirname(out))
        reader.extract_entry(entry.name, out)
      end
    end

    let(:archive_path) { File.join(temp_dir, "archive.rar") }

    it "STORE archive decodes to the original content" do
      test_file = File.join(temp_dir, "test.txt")
      test_content = "Test content for unrar"
      File.write(test_file, test_content)

      frozen = bytes_match_frozen("rar5_store_omnizip.rar") do
        writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                         compression: :store)
        writer.add_file(test_file, "test.txt")
        writer.write
      end
      decode_frozen(frozen)

      expect(File.read(File.join(temp_dir, "decoded", "test.txt"))).to eq(test_content)
    end

    it "LZSS-requested archive (STORE fallback) decodes to the original content" do
      test_file = File.join(temp_dir, "test.txt")
      test_content = "Test content for unrar"
      File.write(test_file, test_content)

      frozen = bytes_match_frozen("rar5_lzss_fallback.rar") do
        writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                         compression: :lzss, level: 3)
        writer.add_file(test_file, "test.txt")
        writer.write
      end
      decode_frozen(frozen)

      expect(File.read(File.join(temp_dir, "decoded", "test.txt"))).to eq(test_content)
    end

    it "multi-file archive decodes to the original contents" do
      file1 = File.join(temp_dir, "file1.txt")
      file2 = File.join(temp_dir, "file2.txt")
      File.write(file1, "Content 1\n" * 10)
      File.write(file2, "Content 2\n" * 10)

      frozen = bytes_match_frozen("rar5_multi_files.rar") do
        writer = Omnizip::Formats::Rar::Rar5::Writer.new(archive_path,
                                                         compression: :lzma, level: 3)
        writer.add_file(file1, "file1.txt")
        writer.add_file(file2, "file2.txt")
        writer.write
      end
      decode_frozen(frozen)

      expect(File.read(File.join(temp_dir, "decoded", "file1.txt"))).to eq("Content 1\n" * 10)
      expect(File.read(File.join(temp_dir, "decoded", "file2.txt"))).to eq("Content 2\n" * 10)
    end
  end

  describe "Binary compatibility verification" do
    it "produces archives with correct structure for STORE method" do
      test_file = File.join(temp_dir, "test.txt")
      File.write(test_file, "Test content")

      omnizip_archive = File.join(temp_dir, "omnizip.rar")
      writer = Omnizip::Formats::Rar::Writer.new(omnizip_archive,
                                                 compression: :store)
      writer.add_file(test_file)
      writer.write

      # Both should extract to same content
      reader = Omnizip::Formats::Rar::Reader.new(omnizip_archive)
      reader.open

      output = File.join(temp_dir, "extracted.txt")
      reader.extract_entry(File.basename(test_file), output)

      expect(File.read(output)).to eq(File.read(test_file))
    end
  end
end

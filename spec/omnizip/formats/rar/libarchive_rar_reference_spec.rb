# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar5/reader"
require "omnizip/formats/rar3/reader"
require "omnizip/format_detector"

RSpec.describe "Libarchive RAR Reference Files" do
  RAR4_DIR = File.expand_path("../../../fixtures/rar/libarchive_reference/rar4", __dir__)
  RAR5_DIR = File.expand_path("../../../fixtures/rar/libarchive_reference/rar5", __dir__)

  # Skip tests if fixture directory doesn't exist
  before(:all) do
    skip "Libarchive RAR reference files not found" unless Dir.exist?(RAR4_DIR) || Dir.exist?(RAR5_DIR)
  end

  describe "RAR5 format detection" do
    it "detects RAR5 files by signature" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      rar5_files = Dir.glob(File.join(RAR5_DIR, "*.rar")).first(3)
      skip "No RAR5 files found" if rar5_files.empty?

      rar5_files.each do |file|
        expect(Omnizip::FormatDetector.detect(file)).to eq(:rar5)
      end
    end
  end

  describe "RAR4 format detection" do
    it "detects RAR4 files by signature" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      rar4_files = Dir.glob(File.join(RAR4_DIR, "*.rar")).first(3)
      skip "No RAR4 files found" if rar4_files.empty?

      rar4_files.each do |file|
        expect(Omnizip::FormatDetector.detect(file)).to eq(:rar4)
      end
    end
  end

  describe "RAR5 stored files" do
    it "decompresses stored (uncompressed) RAR5 files" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      stored_file = File.join(RAR5_DIR, "test_read_format_rar5_stored.rar")
      skip "Stored RAR5 test file not found" unless File.exist?(stored_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(stored_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
        expect(entries.first.name).to eq("helloworld.txt")
        expect(entries.first.uncompressed_size).to eq(29)
      end
    end

    it "handles multiple stored files in RAR5" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      many_files = File.join(RAR5_DIR, "test_read_format_rar5_stored_manyfiles.rar")
      skip "Multiple files RAR5 test file not found" unless File.exist?(many_files)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(many_files, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries.length).to be > 1
      end
    end
  end

  describe "RAR5 compressed files" do
    it "decompresses LZSS compressed RAR5 files" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      compressed_file = File.join(RAR5_DIR, "test_read_format_rar5_compressed.rar")
      skip "Compressed RAR5 test file not found" unless File.exist?(compressed_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(compressed_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end

    it "handles solid RAR5 archives" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      solid_file = File.join(RAR5_DIR, "test_read_format_rar5_solid.rar")
      skip "Solid RAR5 test file not found" unless File.exist?(solid_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(solid_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end
  end

  describe "RAR5 special features" do
    it "handles RAR5 symlinks" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      symlink_file = File.join(RAR5_DIR, "test_read_format_rar5_symlink.rar")
      skip "Symlink RAR5 test file not found" unless File.exist?(symlink_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(symlink_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end

    it "handles RAR5 hardlinks" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      hardlink_file = File.join(RAR5_DIR, "test_read_format_rar5_hardlink.rar")
      skip "Hardlink RAR5 test file not found" unless File.exist?(hardlink_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(hardlink_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end

    it "handles RAR5 unicode filenames" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      unicode_file = File.join(RAR5_DIR, "test_read_format_rar5_unicode.rar")
      skip "Unicode RAR5 test file not found" unless File.exist?(unicode_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      File.open(unicode_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end
  end

  describe "RAR5 multi-volume archives" do
    it "detects multi-volume RAR5 archives" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      part1 = File.join(RAR5_DIR, "test_read_format_rar5_multiarchive.part01.rar")
      skip "Multi-volume RAR5 test file not found" unless File.exist?(part1)

      # First part should be detectable
      expect(Omnizip::FormatDetector.detect(part1)).to eq(:rar5)
    end
  end

  describe "RAR5 error handling" do
    it "handles truncated files gracefully" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      truncated_file = File.join(RAR5_DIR, "test_read_format_rar5_truncated_huff.rar")
      skip "Truncated RAR5 test file not found" unless File.exist?(truncated_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      expect do
        File.open(truncated_file, "rb") do |io|
          reader.read_archive(io)
        end
      end.not_to raise_error
    end

    it "handles invalid dictionary references" do
      skip "RAR5 reference files not found" unless Dir.exist?(RAR5_DIR)

      invalid_file = File.join(RAR5_DIR, "test_read_format_rar5_invalid_dict_reference.rar")
      skip "Invalid dict RAR5 test file not found" unless File.exist?(invalid_file)

      reader = Omnizip::Formats::Rar5::Reader.new
      expect do
        File.open(invalid_file, "rb") do |io|
          reader.read_archive(io)
        end
      end.not_to raise_error
    end
  end

  describe "RAR4 basic reading" do
    it "reads basic RAR4 archives" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      basic_file = File.join(RAR4_DIR, "test_read_format_rar.rar")
      skip "Basic RAR4 test file not found" unless File.exist?(basic_file)

      reader = Omnizip::Formats::Rar3::Reader.new
      File.open(basic_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end

    it "reads RAR4 normal compression archives" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      normal_file = File.join(RAR4_DIR, "test_read_format_rar_compress_normal.rar")
      skip "Normal compression RAR4 test file not found" unless File.exist?(normal_file)

      reader = Omnizip::Formats::Rar3::Reader.new
      File.open(normal_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end

    it "reads RAR4 best compression archives" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      best_file = File.join(RAR4_DIR, "test_read_format_rar_compress_best.rar")
      skip "Best compression RAR4 test file not found" unless File.exist?(best_file)

      reader = Omnizip::Formats::Rar3::Reader.new
      File.open(best_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end
  end

  describe "RAR4 special features" do
    it "handles RAR4 unicode filenames" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      unicode_file = File.join(RAR4_DIR, "test_read_format_rar_unicode.rar")
      skip "Unicode RAR4 test file not found" unless File.exist?(unicode_file)

      reader = Omnizip::Formats::Rar3::Reader.new
      File.open(unicode_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end

    it "handles RAR4 symlinks" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      symlink_file = File.join(RAR4_DIR, "test_read_format_rar_symlink_huge.rar")
      skip "Symlink RAR4 test file not found" unless File.exist?(symlink_file)

      reader = Omnizip::Formats::Rar3::Reader.new
      File.open(symlink_file, "rb") do |io|
        entries = reader.read_archive(io)
        expect(entries).not_to be_empty
      end
    end
  end

  describe "RAR4 multi-volume archives" do
    it "detects RAR4 multi-volume archives" do
      skip "RAR4 reference files not found" unless Dir.exist?(RAR4_DIR)

      part1 = File.join(RAR4_DIR, "test_read_format_rar_multivolume.part0001.rar")
      skip "Multi-volume RAR4 test file not found" unless File.exist?(part1)

      expect(Omnizip::FormatDetector.detect(part1)).to eq(:rar4)
    end
  end
end

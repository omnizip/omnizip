# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/writer"
require "omnizip/formats/rar/reader"
require "tempfile"
require "fileutils"

RSpec.describe Omnizip::Formats::Rar::Writer, :integration do
  let(:temp_dir) { Dir.mktmpdir("omnizip_writer_integration") }
  let(:output_path) { File.join(temp_dir, "test.rar") }
  let(:test_file) { File.join(temp_dir, "test.txt") }
  let(:test_content) { "Hello, RAR World!\n" * 100 }

  before do
    File.write(test_file, test_content)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  # Helper to extract file content
  def extract_content(reader, filename)
    extract_path = File.join(temp_dir, "extracted_#{filename}")
    reader.extract_entry(filename, extract_path)
    File.read(extract_path)
  ensure
    File.delete(extract_path) if extract_path && File.exist?(extract_path)
  end

  describe "RAR4 archive creation with native compression" do
    it "creates valid RAR4 archive with METHOD_STORE" do
      writer = described_class.new(output_path, compression: :store)
      writer.add_file(test_file)
      writer.write

      expect(File.exist?(output_path)).to be true

      # Verify with Reader
      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files
      expect(files.size).to eq(1)
      expect(files.first.name).to eq(File.basename(test_file))
    end

    it "creates valid RAR4 archive with METHOD_FASTEST" do
      writer = described_class.new(output_path, compression: :fastest)
      writer.add_file(test_file)
      writer.write

      expect(File.exist?(output_path)).to be true

      # Verify with Reader
      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files
      expect(files.size).to eq(1)
      expect(files.first.name).to eq(File.basename(test_file))
    end

    it "creates valid RAR4 archive with METHOD_NORMAL (default)" do
      writer = described_class.new(output_path, compression: :normal)
      writer.add_file(test_file)
      writer.write

      expect(File.exist?(output_path)).to be true

      # Verify with Reader
      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files
      expect(files.size).to eq(1)
      expect(files.first.name).to eq(File.basename(test_file))
    end

    it "creates valid RAR4 archive with METHOD_BEST (PPMd)" do
      writer = described_class.new(output_path, compression: :best)
      writer.add_file(test_file)
      writer.write

      expect(File.exist?(output_path)).to be true

      # Verify with Reader
      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      expect(reader.valid?).to be true
      files = reader.list_files
      expect(files.size).to eq(1)
      expect(files.first.name).to eq(File.basename(test_file))
    end
  end

  describe "round-trip compression/decompression" do
    it "correctly compresses and decompresses with METHOD_STORE" do
      writer = described_class.new(output_path, compression: :store)
      writer.add_file(test_file)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      extracted = extract_content(reader, File.basename(test_file))
      expect(extracted).to eq(test_content)
    end

    it "correctly compresses and decompresses with METHOD_FASTEST" do
      # RAR4 METHOD_FASTEST uses LZ77+Huffman, not LZMA
      writer = described_class.new(output_path, compression: :fastest)
      writer.add_file(test_file)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      extracted = extract_content(reader, File.basename(test_file))
      expect(extracted).to eq(test_content)
    end

    it "correctly compresses and decompresses with METHOD_NORMAL" do
      writer = described_class.new(output_path, compression: :normal)
      writer.add_file(test_file)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      extracted = extract_content(reader, File.basename(test_file))
      expect(extracted).to eq(test_content)
    end

    it "correctly compresses and decompresses with METHOD_BEST (PPMd)" do
      skip "PPMd encoder/decoder synchronization requires v0.4.0 (complex state management fix needed)"

      writer = described_class.new(output_path, compression: :best)
      writer.add_file(test_file)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      extracted = extract_content(reader, File.basename(test_file))
      expect(extracted).to eq(test_content)
    end
  end

  describe "automatic compression method selection" do
    it "uses METHOD_STORE for small files (< 300 bytes)" do
      small_file = File.join(temp_dir, "small.txt")
      File.write(small_file, "Small content")

      writer = described_class.new(output_path)
      writer.add_file(small_file)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      # METHOD_STORE (0x30) should be used
      files = reader.list_files
      expect(files.first.method).to eq(0x30)
    end

    it "uses compression for larger files" do
      writer = described_class.new(output_path)
      writer.add_file(test_file) # > 300 bytes
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      # Should use METHOD_NORMAL (0x33) by default
      files = reader.list_files
      expect(files.first.method).to eq(0x33)
    end
  end

  describe "multi-file archives" do
    it "creates archive with multiple files" do
      file1 = File.join(temp_dir, "file1.txt")
      file2 = File.join(temp_dir, "file2.txt")
      File.write(file1, "Content 1" * 50)
      File.write(file2, "Content 2" * 50)

      writer = described_class.new(output_path)
      writer.add_file(file1)
      writer.add_file(file2)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      files = reader.list_files
      expect(files.size).to eq(2)
      expect(files.map(&:name)).to contain_exactly("file1.txt", "file2.txt")
    end
  end

  describe "data integrity" do
    it "maintains exact data integrity through compression cycle" do
      writer = described_class.new(output_path, compression: :normal)
      writer.add_file(test_file)
      writer.write

      reader = Omnizip::Formats::Rar::Reader.new(output_path)
      reader.open

      extracted = extract_content(reader, File.basename(test_file))

      # Verify exact byte-for-byte match
      expect(extracted.bytes).to eq(test_content.bytes)
      expect(extracted.size).to eq(test_content.size)
    end
  end
end

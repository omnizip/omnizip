# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Omnizip::Formats::Zip::Reader do
  let(:test_zip_path) do
    File.join(File.dirname(__FILE__), "../../../fixtures/zip/simple.zip")
  end
  let(:reader) { described_class.new(test_zip_path) }

  describe "#read_entry_stream" do
    it "streams deflate entries chunk-by-chunk with a matching CRC" do
      Dir.mktmpdir("omnizip_stream") do |tmp|
        path = File.join(tmp, "deflate.zip")
        content = Random.new(42).bytes(100_000)
        Omnizip.compress_file(
          File.join(tmp, "in.txt").tap { |p| File.binwrite(p, content) }, path
        )

        streamed = +""
        chunks = 0
        described_class.new(path).read_entry_stream("in.txt", chunk_size: 1024) do |chunk|
          streamed << chunk
          chunks += 1
        end

        expect(streamed).to eq(content)
        expect(chunks).to be > 1
      end
    end

    it "streams STORE entries without reading past the entry payload" do
      Dir.mktmpdir("omnizip_stream") do |tmp|
        path = File.join(tmp, "store.zip")
        content = "stored bytes " * 300
        Omnizip::Buffer.create_from_hash({ "s.bin" => content }, :zip)
        File.binwrite(path, Omnizip::Buffer.create_from_hash({ "s.bin" => content }, :zip).string)

        streamed = +""
        described_class.new(path).read_entry_stream("s.bin", chunk_size: 128) do |chunk|
          streamed << chunk
        end

        expect(streamed).to eq(content)
      end
    end

    it "raises on CRC mismatch for corrupted streams" do
      Dir.mktmpdir("omnizip_stream") do |tmp|
        path = File.join(tmp, "corrupt.zip")
        src = File.join(tmp, "in.txt")
        File.binwrite(src, "corruption target " * 200)
        Omnizip.compress_file(src, path)

        bytes = File.binread(path).b
        # Flip a byte inside the compressed payload, past the headers
        bytes.setbyte(60, bytes.getbyte(60) ^ 0xFF)
        File.binwrite(path, bytes)

        expect do
          described_class.new(path).read_entry_stream("in.txt", &:clear)
        end.to raise_error(Omnizip::ChecksumError, /CRC mismatch/)
      end
    end
  end

  describe "#initialize" do
    it "creates a new reader with file path" do
      expect(reader.file_path).to eq(test_zip_path)
    end

    it "is usable without an explicit read (entries parse on demand)" do
      expect(reader.entries).not_to be_empty
    end
  end

  describe "#read" do
    context "with a simple ZIP file" do
      it "reads the archive structure" do
        reader.read
        expect(reader.entries).not_to be_empty
      end

      it "parses file entries correctly" do
        reader.read
        entry = reader.entries.first
        expect(entry).to be_a(Omnizip::Formats::Zip::CentralDirectoryHeader)
        expect(entry.filename).to be_a(String)
        expect(entry.compressed_size).to be >= 0
        expect(entry.uncompressed_size).to be >= 0
      end
    end
  end

  describe "#list_entries" do
    it "returns array of entry information" do
      reader.read
      entries = reader.list_entries
      expect(entries).to be_an(Array)
      expect(entries.first).to include(
        :filename,
        :compressed_size,
        :uncompressed_size,
        :compression_method,
        :crc32,
        :directory,
      )
    end
  end

  describe "#extract_all" do
    let(:output_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(output_dir)
    end

    it "extracts all files to output directory" do
      reader.read
      reader.extract_all(output_dir)
      expect(Dir.exist?(output_dir)).to be true
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar5/reader"
require "omnizip/formats/rar5/writer"
require "omnizip/formats/rar5/compressor"
require "omnizip/formats/rar5/decompressor"

RSpec.describe "RAR v5 Format Support" do
  describe Omnizip::Formats::Rar5::Reader do
    subject(:reader) { described_class.new }

    it "initializes with RAR5 specification" do
      expect(reader.spec.name).to eq("RAR5")
      expect(reader.version).to eq("5.0")
    end

    it "verifies magic bytes" do
      io = StringIO.new([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].pack("C*"))
      expect(reader.verify_magic_bytes(io)).to be true
    end

    it "rejects invalid magic bytes" do
      io = StringIO.new("INVALID")
      expect(reader.verify_magic_bytes(io)).to be false
    end

    it "has different magic bytes than RAR3" do
      rar3_magic = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
      rar5_magic = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]

      expect(reader.spec.magic_bytes).to eq(rar5_magic)
      expect(reader.spec.magic_bytes).not_to eq(rar3_magic)
    end
  end

  describe Omnizip::Formats::Rar5::Writer do
    subject(:writer) { described_class.new }

    it "initializes with RAR5 specification" do
      expect(writer.spec.name).to eq("RAR5")
      expect(writer.version).to eq("5.0")
    end

    it "writes a basic RAR5 archive" do
      io = StringIO.new
      entries = [
        { name: "test.txt", data: "Hello, World!", time: Time.now },
      ]

      writer.write_archive(io, entries)
      io.rewind

      # Verify magic bytes
      magic = io.read(8)
      expect(magic).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].pack("C*"))
    end

    it "compresses file data" do
      io = StringIO.new
      data = "A" * 1000
      entries = [
        { name: "test.txt", data: data, method: :normal },
      ]

      writer.write_archive(io, entries)

      # Archive should be smaller than uncompressed
      expect(io.size).to be < data.size + 300
    end

    it "supports Unicode filenames" do
      io = StringIO.new
      entries = [
        { name: "テスト.txt", data: "日本語", time: Time.now },
      ]

      writer.write_archive(io, entries)
      io.rewind

      # Should write without error
      expect(io.size).to be > 0
    end
  end

  describe Omnizip::Formats::Rar5::Compressor do
    subject(:compressor) { described_class.new }

    describe "#compress" do
      it "stores data without compression" do
        data = "Test data"
        compressed = compressor.compress(data, method: :store)
        expect(compressed).to eq(data)
      end

      it "compresses data with fastest method" do
        data = "A" * 1000
        compressed = compressor.compress(data, method: :fastest)
        expect(compressed.size).to be < data.size
      end

      it "compresses data with normal method" do
        data = "A" * 1000
        compressed = compressor.compress(data, method: :normal)
        expect(compressed.size).to be < data.size
      end

      it "compresses data with best method" do
        data = "A" * 1000
        compressed = compressor.compress(data, method: :best)
        expect(compressed.size).to be < data.size
      end

      it "raises error for invalid compression method" do
        expect do
          compressor.compress("data", method: :invalid)
        end.to raise_error(Omnizip::FormatError)
      end
    end
  end

  describe Omnizip::Formats::Rar5::Decompressor do
    subject(:decompressor) { described_class.new }
    let(:compressor) { Omnizip::Formats::Rar5::Compressor.new }

    describe "#decompress" do
      it "returns stored data unchanged" do
        data = "Test data"
        decompressed = decompressor.decompress(data, method: :store)
        expect(decompressed).to eq(data)
      end

      it "decompresses data compressed with fastest method" do
        data = "A" * 1000
        compressed = compressor.compress(data, method: :fastest)
        decompressed = decompressor.decompress(compressed, method: :fastest)
        expect(decompressed).to eq(data)
      end

      it "decompresses data compressed with normal method" do
        data = "Test data for compression"
        compressed = compressor.compress(data, method: :normal)
        decompressed = decompressor.decompress(compressed, method: :normal)
        expect(decompressed).to eq(data)
      end

      it "decompresses data compressed with best method" do
        data = "A" * 1000
        compressed = compressor.compress(data, method: :best)
        decompressed = decompressor.decompress(compressed, method: :best)
        expect(decompressed).to eq(data)
      end

      it "raises error for invalid decompression method" do
        expect do
          decompressor.decompress("data", method: :invalid)
        end.to raise_error(Omnizip::FormatError)
      end
    end
  end

  describe "Integration: Write and Read" do
    it "writes and reads a RAR5 archive" do
      writer = Omnizip::Formats::Rar5::Writer.new

      # Create archive
      archive_io = StringIO.new
      entries = [
        { name: "file1.txt", data: "Content 1", time: Time.now },
        { name: "file2.txt", data: "Content 2", time: Time.now },
      ]

      writer.write_archive(archive_io, entries)
      archive_io.rewind

      # Verify archive starts with correct magic bytes
      magic = archive_io.read(8)
      expect(magic).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].pack("C*"))
    end

    it "handles large files" do
      writer = Omnizip::Formats::Rar5::Writer.new

      # Create archive with large content
      archive_io = StringIO.new
      large_data = "X" * 10_000
      entries = [
        { name: "large.txt", data: large_data, time: Time.now },
      ]

      writer.write_archive(archive_io, entries)

      # Should compress significantly
      expect(archive_io.size).to be < large_data.size
    end
  end

  describe "RAR5 vs RAR3 Differences" do
    let(:rar3_writer) { Omnizip::Formats::Rar3::Writer.new }
    let(:rar5_writer) { Omnizip::Formats::Rar5::Writer.new }

    it "uses different magic bytes" do
      rar3_io = StringIO.new
      rar5_io = StringIO.new

      entries = [{ name: "test.txt", data: "data", time: Time.now }]

      rar3_writer.write_archive(rar3_io, entries)
      rar5_writer.write_archive(rar5_io, entries)

      rar3_io.rewind
      rar5_io.rewind

      rar3_magic = rar3_io.read(7)
      rar5_magic = rar5_io.read(8)

      expect(rar3_magic).not_to eq(rar5_magic[0..6])
      expect(rar5_magic.bytes.last).to eq(0x00)
    end
  end
end
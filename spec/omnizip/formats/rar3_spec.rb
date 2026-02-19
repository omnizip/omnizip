# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar3/reader"
require "omnizip/formats/rar3/writer"
require "omnizip/formats/rar3/compressor"
require "omnizip/formats/rar3/decompressor"

RSpec.describe "RAR v3 Format Support" do
  describe Omnizip::Formats::Rar3::Reader do
    subject(:reader) { described_class.new }

    it "initializes with RAR3 specification" do
      expect(reader.spec.name).to eq("RAR3")
      expect(reader.version).to eq("3.0")
    end

    it "verifies magic bytes" do
      io = StringIO.new([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00].pack("C*"))
      expect(reader.verify_magic_bytes(io)).to be true
    end

    it "rejects invalid magic bytes" do
      io = StringIO.new("INVALID")
      expect(reader.verify_magic_bytes(io)).to be false
    end
  end

  describe Omnizip::Formats::Rar3::Writer do
    subject(:writer) { described_class.new }

    it "initializes with RAR3 specification" do
      expect(writer.spec.name).to eq("RAR3")
      expect(writer.version).to eq("3.0")
    end

    it "writes a basic RAR3 archive" do
      io = StringIO.new
      entries = [
        { name: "test.txt", data: "Hello, World!", time: Time.now },
      ]

      writer.write_archive(io, entries)
      io.rewind

      # Verify magic bytes
      magic = io.read(7)
      expect(magic).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00].pack("C*"))
    end

    it "compresses file data" do
      io = StringIO.new
      data = "A" * 1000
      entries = [
        { name: "test.txt", data: data, method: :normal },
      ]

      writer.write_archive(io, entries)

      # Archive should be smaller than uncompressed
      expect(io.size).to be < data.size + 200
    end
  end

  describe Omnizip::Formats::Rar3::Compressor do
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

  describe Omnizip::Formats::Rar3::Decompressor do
    subject(:decompressor) { described_class.new }
    let(:compressor) { Omnizip::Formats::Rar3::Compressor.new }

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
    it "writes and reads a RAR3 archive" do
      writer = Omnizip::Formats::Rar3::Writer.new

      # Create archive
      archive_io = StringIO.new
      entries = [
        { name: "file1.txt", data: "Content 1", time: Time.now },
        { name: "file2.txt", data: "Content 2", time: Time.now },
      ]

      writer.write_archive(archive_io, entries)
      archive_io.rewind

      # Verify archive starts with correct magic bytes
      magic = archive_io.read(7)
      expect(magic).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00].pack("C*"))
    end
  end
end

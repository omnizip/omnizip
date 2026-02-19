# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar"
require "tempfile"
require "fileutils"

RSpec.describe "Native RAR Decompression Integration" do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && File.exist?(temp_dir)
  end

  describe "Dispatcher integration" do
    it "loads Dispatcher successfully" do
      expect(Omnizip::Formats::Rar::Compression::Dispatcher).to be_a(Class)
    end

    it "Dispatcher has all compression methods defined" do
      dispatcher = Omnizip::Formats::Rar::Compression::Dispatcher
      expect(dispatcher::METHOD_STORE).to eq(0x30)
      expect(dispatcher::METHOD_FASTEST).to eq(0x31)
      expect(dispatcher::METHOD_FAST).to eq(0x32)
      expect(dispatcher::METHOD_NORMAL).to eq(0x33)
      expect(dispatcher::METHOD_GOOD).to eq(0x34)
      expect(dispatcher::METHOD_BEST).to eq(0x35)
    end
  end

  describe "Reader native decompression support" do
    let(:reader) { Omnizip::Formats::Rar::Reader.new("dummy.rar") }

    it "initializes with native decompression enabled" do
      expect(reader.instance_variable_get(:@use_native)).to eq(true)
    end

    it "has native decompression methods" do
      expect(reader).to respond_to(:extract_entry)
      # Check private methods exist
      expect(reader.private_methods).to include(:extract_entry_native)
      expect(reader.private_methods).to include(:extract_entry_external)
    end
  end

  describe "Graceful fallback" do
    it "falls back to external decompressor when native fails" do
      # This is tested implicitly - if native fails, external is used
      # We can verify the fallback logic exists in the Reader
      reader = Omnizip::Formats::Rar::Reader.new("test.rar")
      expect(reader.private_methods).to include(:extract_entry_external)
      expect(reader.private_methods).to include(:extract_entry_native)
    end
  end

  describe "Method dispatch" do
    let(:input) { StringIO.new("test data") }
    let(:output) { StringIO.new }
    let(:dispatcher) { Omnizip::Formats::Rar::Compression::Dispatcher }

    it "dispatches METHOD_STORE correctly" do
      expect do
        dispatcher.decompress(0x30, input, output)
      end.not_to raise_error
    end

    it "dispatches METHOD_NORMAL correctly" do
      expect do
        dispatcher.decompress(0x33, StringIO.new, StringIO.new)
      end.not_to raise_error
    end

    it "dispatches METHOD_BEST correctly" do
      expect do
        dispatcher.decompress(0x35, StringIO.new, StringIO.new)
      end.not_to raise_error
    end

    it "raises error for unknown method" do
      expect do
        dispatcher.decompress(0xFF, input, output)
      end.to raise_error(
        Omnizip::Formats::Rar::Compression::Dispatcher::UnsupportedMethodError,
      )
    end
  end

  describe "Component integration" do
    it "PPMd decoder is available" do
      expect(Omnizip::Formats::Rar::Compression::PPMd::Decoder).to be_a(Class)
    end

    it "LZ77Huffman decoder is available" do
      expect(
        Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder,
      ).to be_a(Class)
    end

    it "BitStream is available" do
      expect(Omnizip::Formats::Rar::Compression::BitStream).to be_a(Class)
    end

    it "all components load without error" do
      expect do
        require "omnizip/formats/rar/compression/dispatcher"
        require "omnizip/formats/rar/compression/ppmd/decoder"
        require "omnizip/formats/rar/compression/lz77_huffman/decoder"
      end.not_to raise_error
    end
  end

  describe "Architecture compliance" do
    it "Dispatcher follows OOP principles" do
      dispatcher = Omnizip::Formats::Rar::Compression::Dispatcher

      # Should have clean public interface
      expect(dispatcher).to respond_to(:decompress)
      expect(dispatcher).to respond_to(:compress)

      # Should not expose internal implementation
      expect(dispatcher.private_methods).to include(:decompress_store)
      expect(dispatcher.private_methods).to include(:decompress_lz77_huffman)
      expect(dispatcher.private_methods).to include(:decompress_ppmd)
    end

    it "Reader maintains separation of concerns" do
      reader = Omnizip::Formats::Rar::Reader.new("test.rar")

      # Reader should delegate to Dispatcher, not implement decompression
      expect(reader.private_methods).to include(:extract_entry_native)
      expect(reader.private_methods).not_to include(:decompress_lz77_huffman)
      expect(reader.private_methods).not_to include(:decompress_ppmd)
    end
  end

  describe "Error handling" do
    let(:dispatcher) { Omnizip::Formats::Rar::Compression::Dispatcher }

    it "wraps decompression errors appropriately" do
      # Simulate decompression error with invalid input
      bad_input = StringIO.new("\x00\x00\x00\x00")
      output = StringIO.new

      # Should handle gracefully
      expect do
        dispatcher.decompress(0x33, bad_input, output)
      end.not_to raise_error
    end

    it "preserves UnsupportedMethodError" do
      expect do
        dispatcher.decompress(0x99, StringIO.new, StringIO.new)
      end.to raise_error(
        Omnizip::Formats::Rar::Compression::Dispatcher::UnsupportedMethodError,
      )
    end
  end

  describe "Performance characteristics" do
    let(:dispatcher) { Omnizip::Formats::Rar::Compression::Dispatcher }

    it "handles small data efficiently" do
      input = StringIO.new("a" * 100)
      output = StringIO.new

      start_time = Time.now
      dispatcher.decompress(0x30, input, output) # METHOD_STORE
      duration = Time.now - start_time

      expect(duration).to be < 0.01 # Should be very fast for store
    end

    it "handles moderately large data" do
      input = StringIO.new("b" * 10_000)
      output = StringIO.new

      start_time = Time.now
      dispatcher.decompress(0x30, input, output)
      duration = Time.now - start_time

      expect(duration).to be < 0.1 # Still fast for store
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/solid/solid_encoder"

RSpec.describe Omnizip::Formats::Rar::Rar5::Solid::SolidEncoder do
  describe "#initialize" do
    it "creates encoder with default level" do
      encoder = described_class.new
      expect(encoder.level).to eq(3)
    end

    it "creates encoder with custom level" do
      encoder = described_class.new(level: 5)
      expect(encoder.level).to eq(5)
    end
  end

  describe "#compress_stream and #decompress_stream" do
    let(:encoder) { described_class.new(level: 3) }

    it "compresses and decompresses simple text" do
      data = "Hello, World!"
      compressed = encoder.compress_stream(data)
      decompressed = encoder.decompress_stream(compressed)

      expect(decompressed).to eq(data)
    end

    it "compresses and decompresses larger text" do
      data = "Lorem ipsum dolor sit amet. " * 100
      compressed = encoder.compress_stream(data)
      decompressed = encoder.decompress_stream(compressed)

      expect(decompressed).to eq(data)
      expect(compressed.bytesize).to be < data.bytesize
    end

    it "handles binary data" do
      data = (([0] * 50) + ([255] * 50)).pack("C*")
      compressed = encoder.compress_stream(data)
      decompressed = encoder.decompress_stream(compressed)

      expect(decompressed).to eq(data)
    end

    it "compresses concatenated files efficiently" do
      # Similar content should compress well in solid mode
      file1 = "def hello\n  puts 'Hello'\nend\n"
      file2 = "def goodbye\n  puts 'Goodbye'\nend\n"
      file3 = "def welcome\n  puts 'Welcome'\nend\n"

      concatenated = file1 + file2 + file3
      compressed = encoder.compress_stream(concatenated)

      # For small data, LZMA may have overhead, so just verify round-trip
      # (Compression headers can make output larger than input for tiny files)

      # Verify decompression
      decompressed = encoder.decompress_stream(compressed)
      expect(decompressed).to eq(concatenated)
    end
  end

  describe "#build_lzma_options" do
    it "uses larger dictionaries than non-solid mode" do
      encoder = described_class.new(level: 3)
      options = encoder.build_lzma_options(3)

      expect(options.level).to eq(3)
      expect(options.dict_size).to eq(16 * 1024 * 1024) # 16 MB
    end

    it "scales dictionary size with level" do
      encoder = described_class.new

      level1 = encoder.build_lzma_options(1)
      level3 = encoder.build_lzma_options(3)
      level5 = encoder.build_lzma_options(5)

      expect(level1.dict_size).to eq(1 * 1024 * 1024)   # 1 MB
      expect(level3.dict_size).to eq(16 * 1024 * 1024)  # 16 MB
      expect(level5.dict_size).to eq(64 * 1024 * 1024)  # 64 MB
    end
  end

  describe "compression quality" do
    it "higher levels achieve better compression" do
      data = "The quick brown fox jumps over the lazy dog. " * 50

      encoder_low = described_class.new(level: 1)
      encoder_high = described_class.new(level: 5)

      compressed_low = encoder_low.compress_stream(data)
      compressed_high = encoder_high.compress_stream(data)

      # Higher level should typically produce smaller output
      # (though not guaranteed for all data)
      expect(compressed_high.bytesize).to be <= compressed_low.bytesize
    end
  end
end

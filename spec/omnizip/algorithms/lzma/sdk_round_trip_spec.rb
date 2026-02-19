# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "omnizip/implementations/seven_zip/lzma/encoder"
require "omnizip/implementations/seven_zip/lzma/decoder"

RSpec.describe "7-Zip SDK Encoder/Decoder Round-trip" do
  # These tests verify that the 7-Zip SDK encoder and decoder work together
  # to produce and consume compatible LZMA streams.
  #
  # IMPORTANT: 7-Zip SDK and XZ Utils are DIFFERENT implementations!
  # - 7-Zip SDK: Normalizes AFTER encoding
  # - XZ Utils: Normalizes BEFORE encoding
  # - These produce different byte sequences, so SDK encoder must pair with SDK decoder
  #
  # Reference: /Users/mulgogi/src/external/7-Zip/C/LzmaEnc.c

  let(:sdk_encoder) { Omnizip::Implementations::SevenZip::LZMA::Encoder }
  let(:sdk_decoder) { Omnizip::Implementations::SevenZip::LZMA::Decoder }

  def round_trip(data, options = {})
    encoded = StringIO.new
    encoder = sdk_encoder.new(encoded, options)
    encoder.encode_stream(data)

    encoded.rewind
    decoder = sdk_decoder.new(encoded)
    decoder.decode_stream
  end

  describe "basic round-trip" do
    it "encodes and decodes simple text" do
      data = "Hello, World!"
      expect(round_trip(data)).to eq(data)
    end

    it "handles empty input" do
      data = ""
      expect(round_trip(data)).to eq(data)
    end

    it "handles single byte input" do
      data = "A"
      expect(round_trip(data)).to eq(data)
    end

    it "handles repetitive data" do
      data = "aaaaaaaaaa" * 10
      expect(round_trip(data)).to eq(data)
    end

    it "handles binary data" do
      data = (0..255).to_a.pack("C*")
      expect(round_trip(data)).to eq(data)
    end
  end

  describe "text with matches" do
    it "handles data with repeated patterns" do
      data = "The quick brown fox jumps over the lazy dog."
      expect(round_trip(data)).to eq(data)
    end

    it "handles long matches" do
      data = "Pattern" * 100
      expect(round_trip(data)).to eq(data)
    end

    it "handles newlines" do
      data = "Line 1\nLine 2\nLine 3\n"
      expect(round_trip(data)).to eq(data)
    end

    it "handles newlines and whitespace" do
      data = "  indented\n\ttabbed\n\n\nmultiple blanks"
      expect(round_trip(data)).to eq(data)
    end
  end

  describe "configuration options" do
    it "respects lc parameter" do
      data = "test data for lc"
      expect(round_trip(data, lc: 0)).to eq(data)
      expect(round_trip(data, lc: 8)).to eq(data)
    end

    it "respects pb parameter" do
      data = "test data for pb"
      expect(round_trip(data, pb: 0)).to eq(data)
      expect(round_trip(data, pb: 4)).to eq(data)
    end

    it "respects dict_size parameter" do
      data = "test data for dict_size"
      expect(round_trip(data, dict_size: 4096)).to eq(data)
      expect(round_trip(data, dict_size: 65536)).to eq(data)
    end
  end

  describe "compression verification" do
    it "produces smaller output for repetitive data" do
      data = "A" * 1000
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      expect(encoded.pos).to be < data.bytesize
    end

    it "produces valid LZMA header" do
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded, lc: 3, lp: 0, pb: 2)
      encoder.encode_stream("test")

      encoded.rewind
      header = encoded.read(13)

      # Properties byte: lc + (lp * 9) + (pb * 45)
      # For lc=3, lp=0, pb=2: 3 + 0 + 90 = 93
      expect(header[0].ord).to eq(93)

      # Dictionary size (4 bytes, little-endian)
      dict_size = header[1..4].unpack1("V")
      expect(dict_size).to be > 0

      # Uncompressed size (8 bytes, little-endian)
      # Note: -1 (0xFFFFFFFFFFFFFFFF) means unknown size
      uncompressed_size = header[5..12].unpack1("Q<")
      expect(uncompressed_size).to eq(4).or eq(0xFFFFFFFFFFFFFFFF)
    end
  end

  describe "edge cases" do
    it "handles data with no matches" do
      # Random-ish data that won't have matches
      data = (0..255).to_a.shuffle.pack("C*")
      expect(round_trip(data)).to eq(data)
    end

    it "handles all-same-byte input" do
      data = "\x00" * 1000
      expect(round_trip(data)).to eq(data)
    end

    it "handles mixed content" do
      data = ("ABC" * 50) + (0..255).to_a.pack("C*") + ("XYZ" * 50)
      expect(round_trip(data)).to eq(data)
    end
  end
end

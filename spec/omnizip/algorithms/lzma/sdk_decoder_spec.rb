# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "omnizip/implementations/seven_zip/lzma/encoder"
require "omnizip/implementations/seven_zip/lzma/decoder"

# Tests for 7-Zip SDK LZMA decoder
# IMPORTANT: SDK encoder output must be decoded with SDK decoder, NOT XZ Utils decoder
# - 7-Zip SDK normalizes AFTER encoding
# - XZ Utils normalizes BEFORE encoding
# These produce different byte sequences, so encoder/decoder must be paired correctly
RSpec.describe Omnizip::Implementations::SevenZip::LZMA::Decoder do
  let(:sdk_encoder) { Omnizip::Implementations::SevenZip::LZMA::Encoder }
  let(:sdk_decoder) { described_class }
  describe "SDK decoding" do
    it "decodes simple text" do
      data = "Hello, World!"

      # Encode with SDK encoder
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded, lc: 3, lp: 0, pb: 2)
      encoder.encode_stream(data)

      # Decode with SDK decoder
      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles empty input" do
      data = ""

      # Encode
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      # Decode
      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles single byte input" do
      data = "A"

      # Encode
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      # Decode
      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "respects configuration parameters" do
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded, lc: 4, lp: 2, pb: 3)
      encoder.encode_stream("test")

      encoded.rewind
      decoder = sdk_decoder.new(encoded)

      expect(decoder.lc).to eq(4)
      expect(decoder.lp).to eq(2)
      expect(decoder.pb).to eq(3)
    end

    it "validates parameters" do
      # Create invalid header (pb > 4)
      # Properties formula: props = lc + (lp * 9) + (pb * 45)
      # For pb=5: props = 0 + (0 * 9) + (5 * 45) = 225
      invalid = StringIO.new
      invalid.putc(225) # Invalid: pb=5 (must be 0-4)
      4.times { invalid.putc(0) } # dict size
      8.times { invalid.putc(0xFF) } # uncompressed size

      invalid.rewind

      expect do
        sdk_decoder.new(invalid)
      end.to raise_error(RuntimeError, /pb/)
    end
  end

  describe "round-trip with SdkEncoder" do
    it "decodes SDK-encoded data" do
      data = "The quick brown fox jumps over the lazy dog."

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles repetitive data" do
      data = "aaaaaaaaaa" * 10

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles binary data" do
      data = (0..255).to_a.pack("C*") * 2

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles long matches" do
      data = "Pattern" * 100

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end
  end

  describe "integration with Decoder factory" do
    it "can be accessed via SevenZip implementation" do
      data = "Factory pattern test"

      # Encode with SDK encoder
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      # Decode with SDK decoder via implementation namespace
      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "maintains backward compatibility with header parsing" do
      data = "Backward compatibility test"

      # Encode with SDK encoder
      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded, lc: 3, lp: 0, pb: 2)
      encoder.encode_stream(data)

      # Decode with SDK decoder
      encoded.rewind
      decoder = sdk_decoder.new(encoded)

      # Should expose header attributes
      expect(decoder.lc).to eq(3)
      expect(decoder.lp).to eq(0)
      expect(decoder.pb).to eq(2)
      expect(decoder.dict_size).to be > 0
      expect(decoder.uncompressed_size).to eq(data.bytesize).or eq(0xFFFFFFFFFFFFFFFF)
    end
  end

  describe "literal decoding" do
    it "uses matched literal decoding after matches" do
      # Create data with a match scenario
      data = "abcdefabcdef" # Second "abc" should match first

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "uses unmatched literal decoding at start" do
      data = "abc"

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end
  end

  describe "state machine integration" do
    it "transitions states correctly during decoding" do
      # Mix of literals and matches to exercise state transitions
      data = "abcabcxyzxyz"

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end
  end

  describe "EOS marker" do
    it "detects and handles EOS marker" do
      data = "Test EOS marker"

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
      # Should stop at EOS, not read past it
    end
  end

  describe "edge cases" do
    it "handles all ASCII characters" do
      data = (32..126).map(&:chr).join

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles newlines and whitespace" do
      data = "Line 1\nLine 2\r\nLine 3\t\tTabbed"

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles very short matches" do
      data = "aabbccdd" # Two-byte matches

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end

    it "handles maximum length data within reason" do
      data = "x" * 1000

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      decoded = decoder.decode_stream

      expect(decoded).to eq(data)
    end
  end

  describe "output modes" do
    it "returns string when no output stream provided" do
      data = "String output test"

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded, lc: 3, lp: 0, pb: 2)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)
      result = decoder.decode_stream

      expect(result).to be_a(String)
      expect(result).to eq(data)
    end

    it "writes to output stream when provided" do
      data = "Stream Output test"

      encoded = StringIO.new
      encoder = sdk_encoder.new(encoded, lc: 3, lp: 0, pb: 2)
      encoder.encode_stream(data)

      encoded.rewind
      decoder = sdk_decoder.new(encoded)

      output = StringIO.new
      bytes_written = decoder.decode_stream(output)

      expect(bytes_written).to eq(data.bytesize)
      expect(output.string).to eq(data)
    end
  end
end

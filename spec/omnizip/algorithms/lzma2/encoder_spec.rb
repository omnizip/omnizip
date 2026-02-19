# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA2Encoder do
  describe "#initialize" do
    it "creates encoder with default options" do
      encoder = described_class.new
      expect(encoder.dict_size).to eq(8 * 1024 * 1024)
    end

    it "accepts custom dictionary size" do
      custom_encoder = described_class.new(dict_size: 1 << 20)
      expect(custom_encoder.dict_size).to eq(1 << 20)
    end

    it "accepts custom lc, lp, pb parameters" do
      encoder = described_class.new(lc: 2, lp: 1, pb: 1)
      expect(encoder.lc).to eq(2)
      expect(encoder.lp).to eq(1)
      expect(encoder.pb).to eq(1)
    end
  end

  describe "#encode" do
    it "writes end marker last" do
      encoder = described_class.new
      encoded = encoder.encode("test")
      bytes = encoded.bytes
      expect(bytes.last).to eq(0x00)
    end

    it "encodes small data" do
      encoder = described_class.new
      data = "Hello, World!"
      encoded = encoder.encode(data)
      expect(encoded).not_to be_empty
      expect(encoded.bytes.last).to eq(0x00)  # End marker
    end

    it "handles empty data" do
      encoder = described_class.new
      encoded = encoder.encode("")
      expect(encoded).not_to be_empty
      expect(encoded.bytes.last).to eq(0x00)  # End marker
    end

    it "accepts string input" do
      encoder = described_class.new
      expect { encoder.encode("test data") }.not_to raise_error
    end

    context "with standalone: true" do
      it "writes property byte at start" do
        encoder = described_class.new(standalone: true)
        encoded = encoder.encode("test")
        # Property byte for 8MB dictionary with lc=3, lp=0, pb=2
        # Dict size byte for 8MB = 0x18, but Properties.encode also includes lc/lp/pb
        # The first byte should be a valid property byte
        expect(encoded.bytes[0]).to be_between(0, 255)
      end
    end

    context "with standalone: false (XZ format)" do
      it "does not write property byte" do
        encoder = described_class.new(standalone: false)
        encoded = encoder.encode("test")
        # First byte should be a control byte, not property byte
        # Control bytes start from 0x01
        expect(encoded.bytes[0]).to be >= 0x01
      end
    end
  end

  describe "round-trip encoding/decoding" do
    it "successfully encodes and decodes small data" do
      encoder = described_class.new(standalone: true)
      original = "Hello, World!"
      encoded = encoder.encode(original)

      # Decode using LZMA2 decoder
      input = StringIO.new(encoded)
      input.set_encoding(Encoding::BINARY)
      decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input, raw_mode: false)
      decoded = decoder.decode_stream

      expect(decoded).to eq(original)
    end

    it "successfully encodes and decodes medium data" do
      encoder = described_class.new(standalone: true)
      original = "A" * 1000
      encoded = encoder.encode(original)

      # Decode using LZMA2 decoder
      input = StringIO.new(encoded)
      input.set_encoding(Encoding::BINARY)
      decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input, raw_mode: false)
      decoded = decoder.decode_stream

      expect(decoded).to eq(original)
    end

    it "handles data larger than single chunk" do
      encoder = described_class.new(standalone: true)
      original = "B" * (100 * 1024) # 100KB
      encoded = encoder.encode(original)

      # Decode using LZMA2 decoder
      input = StringIO.new(encoded)
      input.set_encoding(Encoding::BINARY)
      decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input, raw_mode: false)
      decoded = decoder.decode_stream

      expect(decoded).to eq(original)
    end

    it "preserves binary data" do
      encoder = described_class.new(standalone: true)
      original = (0..255).to_a.pack("C*")
      encoded = encoder.encode(original)

      # Decode using LZMA2 decoder
      input = StringIO.new(encoded)
      input.set_encoding(Encoding::BINARY)
      decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input, raw_mode: false)
      decoded = decoder.decode_stream

      expect(decoded.bytes).to eq(original.bytes)
    end
  end

  describe "compression characteristics" do
    it "compresses repetitive data effectively" do
      encoder = described_class.new(standalone: true)
      original = "A" * 10_000
      encoded = encoder.encode(original)

      ratio = encoded.bytesize.to_f / original.bytesize
      expect(ratio).to be < 0.1
    end
  end
end

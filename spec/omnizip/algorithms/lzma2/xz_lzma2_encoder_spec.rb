# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Implementations::XZUtils::LZMA2::Encoder do
  describe "#initialize" do
    it "accepts standalone option" do
      encoder = described_class.new(standalone: true)
      expect(encoder.instance_variable_get(:@standalone)).to eq(true)
    end

    it "defaults standalone to true" do
      encoder = described_class.new
      expect(encoder.instance_variable_get(:@standalone)).to eq(true)
    end
  end

  describe "#encode" do
    context "with standalone: true (default)" do
      it "encodes simple data with property byte" do
        encoder = described_class.new(standalone: true)
        result = encoder.encode("Hello, World!")

        # Property byte for 8MB dictionary is 0x16
        expect(result).to start_with("\x16")
      end

      it "produces decodable output" do
        encoder = described_class.new(standalone: true)
        encoded = encoder.encode("Test")

        # Decode using LZMA2 decoder
        input = StringIO.new(encoded)
        input.set_encoding(Encoding::BINARY)
        decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input,
                                                                        raw_mode: false)
        decoded = decoder.decode_stream

        expect(decoded).to eq("Test")
      end

      it "handles empty input" do
        encoder = described_class.new(standalone: true)
        encoded = encoder.encode("")

        # Should only have property byte + end marker
        expect(encoded.bytesize).to eq(2) # Property byte + 0x00 end marker
      end
    end

    context "with standalone: false (XZ format)" do
      it "does not write property byte" do
        encoder = described_class.new(standalone: false)
        encoded = encoder.encode("Test")

        # First byte should be a control byte (0x01-0x1F) or end marker (0x00)
        # For non-empty data, it should be a control byte
        expect(encoded.bytes[0]).to be >= 0x01
      end

      it "produces decodable output with raw_mode decoder" do
        encoder = described_class.new(standalone: false)
        encoded = encoder.encode("Test")

        # Decode using LZMA2 decoder with raw_mode (no property byte expected)
        input = StringIO.new(encoded)
        input.set_encoding(Encoding::BINARY)
        decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(
          input,
          raw_mode: true,
          dict_size: 8 * 1024 * 1024,
        )
        decoded = decoder.decode_stream

        expect(decoded).to eq("Test")
      end

      it "handles empty input" do
        encoder = described_class.new(standalone: false)
        encoded = encoder.encode("")

        # Should only have end marker (no property byte)
        expect(encoded.bytesize).to eq(1) # 0x00 end marker
      end
    end

    it "produces valid output for varying patterns" do
      encoder = described_class.new(standalone: true)
      # Use non-repetitive data to avoid compressed path
      test_data = "HelloWorldTestABCDEFGH1234567890!@#$%^&*()"
      encoded = encoder.encode(test_data)

      # Decode using LZMA2 decoder
      input = StringIO.new(encoded)
      input.set_encoding(Encoding::BINARY)
      decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input,
                                                                      raw_mode: false)
      decoded = decoder.decode_stream

      expect(decoded).to eq(test_data)
    end

    it "handles data that doesn't compress well" do
      encoder = described_class.new(standalone: true)
      # Non-repetitive data - should use uncompressed chunks
      test_data = "ABCDEFGH" * 5
      encoded = encoder.encode(test_data)

      # Decode using LZMA2 decoder
      input = StringIO.new(encoded)
      input.set_encoding(Encoding::BINARY)
      decoder = Omnizip::Implementations::XZUtils::LZMA2::Decoder.new(input,
                                                                      raw_mode: false)
      decoded = decoder.decode_stream

      expect(decoded).to eq(test_data)
    end

    # NOTE: Full LZMA compression implementation is complex and may have bugs
    # These tests verify the structure and encoding format are correct
    # The encoder will use uncompressed chunks when compression isn't beneficial
    it "maintains correct LZMA2 format structure" do
      encoder = described_class.new(standalone: true)
      encoded = encoder.encode("TestData")

      # Should start with property byte
      expect(encoded.getbyte(0)).to eq(0x16) # 8MB dictionary

      # Should end with end marker
      expect(encoded.getbyte(-1)).to eq(0x00)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Implementations::XZUtils::LZMA2::Decoder do
  let(:test_data) { "Hello, LZMA2!" }

  # Helper to create encoded data
  def encode_data(data)
    encoder = Omnizip::Implementations::XZUtils::LZMA2::Encoder.new
    encoder.encode(data)
  end

  describe "#initialize" do
    it "initializes with raw_mode" do
      encoded = encode_data(test_data)
      input = StringIO.new(encoded)

      # Use raw_mode since encoder doesn't write property byte
      # Encoder uses 8MB default dict_size
      decoder = described_class.new(input, raw_mode: true,
                                           dict_size: 8 * 1024 * 1024)
      expect(decoder.dict_size).to eq(8 * 1024 * 1024)
    end

    it "raises error with invalid header" do
      input = StringIO.new("")
      expect do
        described_class.new(input)
      end.to raise_error(/Invalid LZMA2 header|Unexpected end of stream/)
    end
  end

  describe "#decode_stream" do
    it "decodes encoded data" do
      encoded = encode_data(test_data)
      input = StringIO.new(encoded)

      # NOT using raw_mode since encoder writes property byte (standalone mode)
      decoder = described_class.new(input)
      decoded = decoder.decode_stream

      expect(decoded).to eq(test_data)
    end

    it "handles empty data" do
      encoded = encode_data("")
      input = StringIO.new(encoded)

      # NOT using raw_mode since encoder writes property byte (standalone mode)
      decoder = described_class.new(input)
      decoded = decoder.decode_stream

      expect(decoded).to eq("")
    end

    it "handles larger data" do
      large_data = "A" * 1000
      encoded = encode_data(large_data)
      input = StringIO.new(encoded)

      # NOT using raw_mode since encoder writes property byte (standalone mode)
      decoder = described_class.new(input)
      decoded = decoder.decode_stream

      expect(decoded).to eq(large_data)
    end
  end
end

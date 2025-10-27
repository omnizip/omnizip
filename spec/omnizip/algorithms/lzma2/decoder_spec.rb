# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA2::Decoder do
  let(:test_data) { "Hello, LZMA2!" }

  # Helper to create encoded data
  def encode_data(data)
    output = StringIO.new
    encoder = Omnizip::Algorithms::LZMA2::Encoder.new(output)
    encoder.encode_stream(data)
    output.string
  end

  describe "#initialize" do
    it "reads property byte from input" do
      encoded = encode_data(test_data)
      input = StringIO.new(encoded)

      decoder = described_class.new(input)
      expect(decoder.dict_size).to be > 0
    end

    it "raises error with invalid header" do
      input = StringIO.new("")
      expect do
        described_class.new(input)
      end.to raise_error(/Invalid LZMA2 header/)
    end
  end

  describe "#decode_stream" do
    it "decodes encoded data" do
      encoded = encode_data(test_data)
      input = StringIO.new(encoded)

      decoder = described_class.new(input)
      decoded = decoder.decode_stream

      expect(decoded).to eq(test_data)
    end

    it "handles empty data" do
      encoded = encode_data("")
      input = StringIO.new(encoded)

      decoder = described_class.new(input)
      decoded = decoder.decode_stream

      expect(decoded).to eq("")
    end

    it "handles larger data" do
      large_data = "A" * 1000
      encoded = encode_data(large_data)
      input = StringIO.new(encoded)

      decoder = described_class.new(input)
      decoded = decoder.decode_stream

      expect(decoded).to eq(large_data)
    end
  end
end

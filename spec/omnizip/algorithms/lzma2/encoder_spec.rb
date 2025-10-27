# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA2::Encoder do
  let(:output) { StringIO.new }
  let(:encoder) { described_class.new(output) }

  describe "#initialize" do
    it "creates encoder with default options" do
      expect(encoder.dict_size).to eq(1 << 23)
      expect(encoder.chunk_size).to eq(2 * 1024 * 1024)
    end

    it "accepts custom dictionary size" do
      custom_encoder = described_class.new(output, dict_size: 1 << 20)
      expect(custom_encoder.dict_size).to eq(1 << 20)
    end

    it "accepts custom chunk size" do
      custom_encoder = described_class.new(output, chunk_size: 1 << 20)
      expect(custom_encoder.chunk_size).to eq(1 << 20)
    end
  end

  describe "#encode_stream" do
    it "writes property byte first" do
      encoder.encode_stream("test")
      output.rewind
      prop_byte = output.getbyte
      expect(prop_byte).to be_between(0, 40)
    end

    it "writes end marker last" do
      encoder.encode_stream("test")
      output.rewind
      bytes = output.read.bytes
      expect(bytes.last).to eq(0x00)
    end

    it "encodes small data in single chunk" do
      data = "Hello, World!"
      encoder.encode_stream(data)
      expect(output.string).not_to be_empty
    end

    it "handles empty data" do
      encoder.encode_stream("")
      expect(output.string).not_to be_empty
    end

    it "accepts string input" do
      expect { encoder.encode_stream("test data") }.not_to raise_error
    end

    it "accepts IO input" do
      input = StringIO.new("test data")
      expect { encoder.encode_stream(input) }.not_to raise_error
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::LZMA::XZRangeEncoder do
  describe "#initialize" do
    it "initializes with output stream" do
      output = StringIO.new
      encoder = described_class.new(output)
      expect(encoder.range).to eq(0xFFFFFFFF)
    end
  end

  describe "#encode_bit" do
    it "encodes bit 0 with probability" do
      output = StringIO.new
      encoder = described_class.new(output)
      model = Omnizip::Algorithms::LZMA::BitModel.new

      encoder.encode_bit(model, 0)

      # Probability should stay same or increase (more likely to be 0)
      expect(model.probability).to be >= 1024
    end

    it "encodes bit 1 with probability" do
      output = StringIO.new
      encoder = described_class.new(output)
      model = Omnizip::Algorithms::LZMA::BitModel.new

      encoder.encode_bit(model, 1)

      # Probability should decrease
      expect(model.probability).to be < 1024
    end
  end

  describe "#encode_bittree" do
    it "encodes 8-bit value" do
      output = StringIO.new
      encoder = described_class.new(output)
      models = Array.new(0x300) { Omnizip::Algorithms::LZMA::BitModel.new }

      encoder.encode_bittree(models, 8, 65) # 'A'
      encoder.flush!

      # Should have encoded 8 bits and flushed output
      expect(output.string.bytesize).to be > 0
    end
  end

  describe "#flush!" do
    it "produces output" do
      output = StringIO.new
      encoder = described_class.new(output)
      model = Omnizip::Algorithms::LZMA::BitModel.new

      encoder.encode_bit(model, 0)
      encoder.flush!

      expect(output.string.bytesize).to be > 0
    end
  end
end

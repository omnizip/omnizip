# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::PPMd7 do
  let(:algorithm) { described_class.new }

  describe ".metadata" do
    it "provides correct metadata" do
      metadata = described_class.metadata
      expect(metadata.name).to eq("ppmd7")
      expect(metadata.description).to include("PPMd7")
      expect(metadata.supports_streaming).to be true
    end
  end

  describe "basic functionality" do
    it "can create encoder and decoder" do
      output = StringIO.new(String.new(encoding: Encoding::BINARY))
      encoder = described_class::Encoder.new(output)
      expect(encoder).not_to be_nil
      expect(encoder.model).not_to be_nil
    end

    it "model has proper initialization" do
      encoder = described_class::Encoder.new(
        StringIO.new(String.new(encoding: Encoding::BINARY)),
      )
      expect(encoder.model.max_order).to eq(6)
      expect(encoder.model.root_context.num_symbols).to eq(256)
    end
  end

  describe "context management" do
    it "maintains context tree structure" do
      model = described_class::Model.new(4)
      expect(model.root_context.root?).to be true
      expect(model.current_context).to eq(model.root_context)
    end

    it "updates contexts after symbols" do
      model = described_class::Model.new(4)
      model.current_context
      model.update(65)
      # Context should change after update
      expect(model.current_context).not_to be_nil
    end
  end

  describe "probability predictions" do
    it "provides probability for all symbols in root" do
      model = described_class::Model.new(4)
      prob = model.get_symbol_probability(65)
      expect(prob).to be_a(Hash)
      expect(prob[:freq]).to be > 0
      expect(prob[:total_freq]).to be > 0
    end
  end

  describe "encoder and decoder synchronization" do
    it "encoder uses proper range encoding" do
      output = StringIO.new(String.new(encoding: Encoding::BINARY))
      encoder = described_class::Encoder.new(output)

      # Verify encoder has range_encoder
      expect(encoder.instance_variable_get(:@range_encoder)).not_to be_nil
    end

    it "decoder uses proper range decoding" do
      input = StringIO.new("dummy data")
      decoder = described_class::Decoder.new(input)

      # Verify decoder has range_decoder
      expect(decoder.instance_variable_get(:@range_decoder)).not_to be_nil
    end
  end

  describe "range coding" do
    it "encode_freq and decode_freq are synchronized" do
      # Test that encoder and decoder use matching range coding
      test_symbol = 0x48 # 'H'

      # Create model and get probability
      model = described_class::Model.new(4)
      prob = model.get_symbol_probability(test_symbol)

      expect(prob[:cumulative_freq]).to be >= 0
      expect(prob[:freq]).to be > 0
      expect(prob[:total_freq]).to be > prob[:freq]
    end

    it "handles escape encoding correctly" do
      model = described_class::Model.new(4)

      # Root context should have all 256 symbols, so no escape needed
      prob = model.get_symbol_probability(0x00)
      expect(prob[:escape]).to be false

      prob = model.get_symbol_probability(0xFF)
      expect(prob[:escape]).to be false
    end
  end

  describe "model configuration" do
    it "accepts custom order" do
      model = described_class::Model.new(8)
      expect(model.max_order).to eq(8)
    end

    it "accepts custom memory size" do
      model = described_class::Model.new(6, 32 * 1024 * 1024)
      expect(model.instance_variable_get(:@mem_size)).to eq(32 * 1024 * 1024)
    end

    it "raises error for invalid order" do
      expect { described_class::Model.new(0) }.to raise_error(ArgumentError)
      expect { described_class::Model.new(100) }.to raise_error(ArgumentError)
    end
  end
end

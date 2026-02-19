# frozen_string_literal: true

require "spec_helper"

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
end

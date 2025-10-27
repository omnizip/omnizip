# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::PPMd7::SymbolState do
  describe "#initialize" do
    it "creates a state with symbol and frequency" do
      state = described_class.new(65, 5)
      expect(state.symbol).to eq(65)
      expect(state.freq).to eq(5)
    end

    it "defaults frequency to 1" do
      state = described_class.new(65)
      expect(state.freq).to eq(1)
    end
  end

  describe "#probability" do
    it "calculates probability based on total frequency" do
      state = described_class.new(65, 10)
      prob = state.probability(100)
      expect(prob).to eq(0.1)
    end

    it "handles edge case of single frequency" do
      state = described_class.new(65, 1)
      prob = state.probability(1)
      expect(prob).to eq(1.0)
    end
  end

  describe "#freq=" do
    it "allows updating frequency" do
      state = described_class.new(65, 1)
      state.freq = 10
      expect(state.freq).to eq(10)
    end
  end
end

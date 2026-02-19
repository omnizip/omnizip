# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::BitModel do
  describe "#initialize" do
    it "initializes with default probability" do
      model = described_class.new
      expect(model.probability).to eq(1024)
    end
  end

  describe "#update" do
    it "increases probability after encoding 0 bit when not at midpoint" do
      model = described_class.new(512) # Start below midpoint
      model.update(0)
      expect(model.probability).to be > 512
    end

    it "increases probability toward BIT_MODEL_TOTAL after encoding 0 bit" do
      model = described_class.new
      initial_prob = model.probability
      model.update(0)
      # XZ Utils formula: prob += (BIT_MODEL_TOTAL - prob) >> MOVE_BITS
      # With BIT_MODEL_TOTAL = 2048, PROB_INIT = 1024
      # prob = 1024 + (2048 - 1024) >> 5 = 1024 + 32 = 1056
      expect(model.probability).to eq(initial_prob + ((Omnizip::Algorithms::LZMA::BitModel::BIT_MODEL_TOTAL - initial_prob) >> 5))
    end

    it "decreases probability after encoding 1 bit" do
      model = described_class.new
      model.update(1)
      expect(model.probability).to be < 1024
    end

    it "stays within valid range after many updates" do
      model = described_class.new
      100.times { model.update(0) }
      expect(model.probability).to be_between(0, Omnizip::Algorithms::LZMA::BitModel::MAX_PROB)
    end

    it "matches XZ Utils probability update formula for bit 0" do
      model = described_class.new(1024) # PROB_INIT
      model.update(0)
      # XZ Utils: prob += (RC_BIT_MODEL_TOTAL - prob) >> RC_MOVE_BITS
      # where RC_BIT_MODEL_TOTAL = 2048, RC_MOVE_BITS = 5
      # prob = 1024 + (2048 - 1024) >> 5 = 1024 + 32 = 1056
      expect(model.probability).to eq(1056)
    end

    it "matches XZ Utils probability update formula for bit 1" do
      model = described_class.new(1024) # PROB_INIT
      model.update(1)
      # XZ Utils: prob -= prob >> RC_MOVE_BITS
      # prob = 1024 - (1024 >> 5) = 1024 - 32 = 992
      expect(model.probability).to eq(992)
    end
  end

  describe "#to_range" do
    it "returns probability in range coder format" do
      model = described_class.new
      expect(model.to_range).to eq(1024)
    end
  end
end

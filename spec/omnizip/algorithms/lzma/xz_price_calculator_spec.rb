# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::XzPriceCalculator do
  let(:calculator) { described_class.new }

  describe "PRICE_TABLE" do
    it "is precomputed and frozen" do
      expect(described_class::PRICE_TABLE).to be_frozen
      expect(described_class::PRICE_TABLE.size).to eq(128) # BIT_MODEL_TOTAL >> 4
    end

    it "contains monotonically decreasing values" do
      # Higher probabilities should have lower prices
      (1...described_class::PRICE_TABLE.size).each do |i|
        expect(described_class::PRICE_TABLE[i]).to be <= described_class::PRICE_TABLE[i - 1]
      end
    end

    it "has reasonable price values" do
      # Prices should be positive and bounded
      described_class::PRICE_TABLE.each do |price|
        expect(price).to be >= 0
        expect(price).to be < (16 << described_class::PRICE_SHIFT_BITS)
      end
    end

    it "price at 0.5 probability is approximately log2(2) * scale" do
      # Index for prob = BIT_MODEL_TOTAL / 2
      mid_idx = described_class::PRICE_TABLE_SIZE / 2
      price = described_class::PRICE_TABLE[mid_idx]

      # Expected: -log2(0.5) * PRICE_SCALE = 1.0 * 16 = 16
      # Allow some tolerance for integer approximation
      expect(price).to be_within(2).of(1 << described_class::PRICE_SHIFT_BITS)
    end
  end

  describe ".bit_price" do
    let(:init_prob) { Omnizip::Algorithms::LZMA::Constants::INIT_PROBS }

    it "calculates price for bit 0" do
      price = described_class.bit_price(init_prob, 0)
      expect(price).to be_a(Integer)
      expect(price).to be > 0
    end

    it "calculates price for bit 1" do
      price = described_class.bit_price(init_prob, 1)
      expect(price).to be_a(Integer)
      expect(price).to be > 0
    end

    it "bit 0 and bit 1 have equal price at 0.5 probability" do
      price_0 = described_class.bit_price(init_prob, 0)
      price_1 = described_class.bit_price(init_prob, 1)
      expect(price_0).to eq(price_1)
    end

    it "bit 0 is cheaper with high prob (favors 0)" do
      high_prob = (Omnizip::Algorithms::LZMA::Constants::BIT_MODEL_TOTAL * 3) / 4
      price_0 = described_class.bit_price(high_prob, 0)
      price_1 = described_class.bit_price(high_prob, 1)
      expect(price_0).to be < price_1
    end

    it "bit 1 is cheaper with low prob (favors 1)" do
      low_prob = Omnizip::Algorithms::LZMA::Constants::BIT_MODEL_TOTAL / 4
      price_0 = described_class.bit_price(low_prob, 0)
      price_1 = described_class.bit_price(low_prob, 1)
      expect(price_1).to be < price_0
    end

    it "handles edge case: prob = 0 (maximum price for 0)" do
      # Very unlikely to encode 0
      price = described_class.bit_price(0, 0)
      expect(price).to be > 100 # Should be expensive
    end

    it "handles edge case: prob = BIT_MODEL_TOTAL (maximum price for 1)" do
      # Very unlikely to encode 1
      max_prob = Omnizip::Algorithms::LZMA::Constants::BIT_MODEL_TOTAL - 1
      price = described_class.bit_price(max_prob, 1)
      expect(price).to be > 100 # Should be expensive
    end
  end

  describe ".bittree_price" do
    it "calculates price for encoding symbol in bit tree" do
      # Create simple bit models
      models = Array.new(8) { Omnizip::Algorithms::LZMA::BitModel.new }
      price = described_class.bittree_price(models, 3, 5) # Encode 101 (5)

      expect(price).to be_a(Integer)
      expect(price).to be > 0
    end

    it "price increases with more bits" do
      models = Array.new(256) { Omnizip::Algorithms::LZMA::BitModel.new }

      price_3bits = described_class.bittree_price(models, 3, 0)
      price_8bits = described_class.bittree_price(models, 8, 0)

      expect(price_8bits).to be > price_3bits
    end

    it "different symbols have similar prices with uniform probabilities" do
      models = Array.new(16) { Omnizip::Algorithms::LZMA::BitModel.new }

      price_0 = described_class.bittree_price(models, 3, 0)
      price_7 = described_class.bittree_price(models, 3, 7)

      # Should be close since all probabilities are 0.5
      expect((price_0 - price_7).abs).to be < 5
    end

    it "handles single bit (num_bits = 1)" do
      models = Array.new(2) { Omnizip::Algorithms::LZMA::BitModel.new }

      price_0 = described_class.bittree_price(models, 1, 0)
      price_1 = described_class.bittree_price(models, 1, 1)

      expect(price_0).to be > 0
      expect(price_1).to be > 0
    end
  end

  describe ".bittree_reverse_price" do
    it "calculates price for reverse bit tree encoding" do
      models = Array.new(16) { Omnizip::Algorithms::LZMA::BitModel.new }
      price = described_class.bittree_reverse_price(models, 4, 10)

      expect(price).to be_a(Integer)
      expect(price).to be > 0
    end

    it "price increases with more bits" do
      models = Array.new(256) { Omnizip::Algorithms::LZMA::BitModel.new }

      price_3bits = described_class.bittree_reverse_price(models, 3, 0)
      price_8bits = described_class.bittree_reverse_price(models, 8, 0)

      expect(price_8bits).to be > price_3bits
    end

    it "handles alignment encoding (4 bits)" do
      # Distance alignment uses 4-bit reverse encoding
      models = Array.new(16) { Omnizip::Algorithms::LZMA::BitModel.new }

      (0..15).each do |symbol|
        price = described_class.bittree_reverse_price(models, 4, symbol)
        expect(price).to be > 0
      end
    end
  end

  describe ".direct_price" do
    it "calculates price for direct bits" do
      price = described_class.direct_price(5)
      expect(price).to be_a(Integer)
      expect(price).to be > 0
    end

    it "price is proportional to number of bits" do
      price_1 = described_class.direct_price(1)
      price_5 = described_class.direct_price(5)
      price_10 = described_class.direct_price(10)

      expect(price_5).to eq(price_1 * 5)
      expect(price_10).to eq(price_1 * 10)
    end

    it "single direct bit costs 64 units" do
      # Each direct bit = probability 0.5 = 1 bit of information = 16 * 4 = 64
      price = described_class.direct_price(1)
      expect(price).to eq(64)
    end

    it "handles zero bits" do
      price = described_class.direct_price(0)
      expect(price).to eq(0)
    end

    it "handles many direct bits" do
      # Distance encoding can use up to 26 direct bits
      price = described_class.direct_price(26)
      expect(price).to eq(26 * 64)
    end
  end

  describe "instance methods" do
    it "delegates bit_price to class method" do
      prob = 1024
      bit = 0
      expect(calculator.bit_price(prob,
                                  bit)).to eq(described_class.bit_price(prob,
                                                                        bit))
    end

    it "delegates bittree_price to class method" do
      models = Array.new(8) { Omnizip::Algorithms::LZMA::BitModel.new }
      expect(calculator.bittree_price(models, 3, 5))
        .to eq(described_class.bittree_price(models, 3, 5))
    end

    it "delegates bittree_reverse_price to class method" do
      models = Array.new(16) { Omnizip::Algorithms::LZMA::BitModel.new }
      expect(calculator.bittree_reverse_price(models, 4, 10))
        .to eq(described_class.bittree_reverse_price(models, 4, 10))
    end

    it "delegates direct_price to class method" do
      expect(calculator.direct_price(8)).to eq(described_class.direct_price(8))
    end
  end

  describe "price accuracy" do
    it "prices reflect information content" do
      # Encoding a very likely bit (prob near BIT_MODEL_TOTAL) should be cheap
      high_prob = 2000 # Very high probability for 0
      low_prob = 48 # Very low probability for 0

      cheap_price = described_class.bit_price(high_prob, 0)
      expensive_price = described_class.bit_price(low_prob, 0)

      expect(cheap_price).to be < expensive_price
      expect(expensive_price).to be > cheap_price * 2
    end

    it "total price for complete symbol encoding is sum of bit prices" do
      # Manually calculate price for encoding 3-bit symbol 5 (101)
      models = Array.new(8) { Omnizip::Algorithms::LZMA::BitModel.new }

      # Symbol 5 = 101, tree path: 1(root) → 10 → 101
      manual_price = 0
      manual_price += described_class.bit_price(models[1].probability, 1)   # Bit 2: 1
      manual_price += described_class.bit_price(models[2].probability, 0)   # Bit 1: 0
      manual_price += described_class.bit_price(models[4].probability, 1)   # Bit 0: 1

      auto_price = described_class.bittree_price(models, 3, 5)

      expect(auto_price).to eq(manual_price)
    end
  end
end

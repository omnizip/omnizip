# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::PPMd7::Context do
  describe "#initialize" do
    it "creates a context with order and suffix" do
      root = described_class.new(-1)
      context = described_class.new(0, root)

      expect(context.order).to eq(0)
      expect(context.suffix).to eq(root)
      expect(context.states).to be_empty
    end

    it "initializes with escape frequency" do
      context = described_class.new(0)
      expect(context.escape_freq).to eq(1)
    end
  end

  describe "#add_symbol" do
    let(:context) { described_class.new(0) }

    it "adds a new symbol with frequency" do
      state = context.add_symbol(65, 5)
      expect(state.symbol).to eq(65)
      expect(state.freq).to eq(5)
      expect(context.sum_freq).to eq(5)
    end

    it "raises error for duplicate symbol" do
      context.add_symbol(65)
      expect { context.add_symbol(65) }.to raise_error(ArgumentError)
    end
  end

  describe "#find_symbol" do
    let(:context) { described_class.new(0) }

    it "finds existing symbol" do
      context.add_symbol(65, 5)
      state = context.find_symbol(65)
      expect(state).not_to be_nil
      expect(state.freq).to eq(5)
    end

    it "returns nil for non-existent symbol" do
      expect(context.find_symbol(99)).to be_nil
    end
  end

  describe "#update_symbol" do
    let(:context) { described_class.new(0) }

    it "increases symbol frequency" do
      context.add_symbol(65, 1)
      context.update_symbol(65, 3)
      expect(context.find_symbol(65).freq).to eq(4)
      expect(context.sum_freq).to eq(4)
    end

    it "does nothing for non-existent symbol" do
      context.update_symbol(99)
      expect(context.sum_freq).to eq(0)
    end
  end

  describe "#total_freq" do
    let(:context) { described_class.new(0) }

    it "returns sum of frequencies plus escape" do
      context.add_symbol(65, 10)
      context.add_symbol(66, 20)
      expect(context.total_freq).to eq(31) # 10 + 20 + 1 (escape)
    end
  end

  describe "#root?" do
    it "returns true for root context" do
      root = described_class.new(-1, nil)
      expect(root.root?).to be true
    end

    it "returns false for non-root context" do
      root = described_class.new(-1, nil)
      context = described_class.new(0, root)
      expect(context.root?).to be false
    end
  end

  describe "#num_symbols" do
    let(:context) { described_class.new(0) }

    it "returns number of distinct symbols" do
      context.add_symbol(65)
      context.add_symbol(66)
      context.add_symbol(67)
      expect(context.num_symbols).to eq(3)
    end
  end
end

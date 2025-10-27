# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::PPMd7::Model do
  describe "#initialize" do
    it "creates model with default parameters" do
      model = described_class.new
      expect(model.max_order).to eq(6)
      expect(model.root_context).not_to be_nil
    end

    it "creates model with custom order" do
      model = described_class.new(4)
      expect(model.max_order).to eq(4)
    end

    it "rejects invalid order" do
      expect { described_class.new(1) }.to raise_error(ArgumentError)
      expect { described_class.new(20) }.to raise_error(ArgumentError)
    end

    it "initializes root context with all symbols" do
      model = described_class.new
      expect(model.root_context.num_symbols).to eq(256)
    end
  end

  describe "#get_symbol_probability" do
    let(:model) { described_class.new(4) }

    it "returns probability for symbol in root context" do
      prob = model.get_symbol_probability(65)
      expect(prob[:escape]).to be false
      expect(prob[:freq]).to be > 0
      expect(prob[:total_freq]).to be > 0
    end
  end

  describe "#update" do
    let(:model) { described_class.new(4) }

    it "updates model after processing symbol" do
      initial_context = model.current_context
      model.update(65)
      # Context should change after update
      expect(model.current_context).not_to eq(initial_context)
    end
  end

  describe "#reset" do
    let(:model) { described_class.new(4) }

    it "resets model to initial state" do
      model.update(65)
      model.update(66)
      model.reset
      expect(model.current_context).to eq(model.root_context)
      expect(model.root_context.num_symbols).to eq(256)
    end
  end
end

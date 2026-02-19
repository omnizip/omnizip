# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Compression::PPMd::Context do
  describe "#initialize" do
    it "initializes with RAR escape frequency" do
      context = described_class.new(0)

      # RAR variant H uses escape frequency of 1
      expect(context.escape_freq).to eq(1)
    end

    it "accepts order parameter" do
      context = described_class.new(5)

      expect(context.order).to eq(5)
    end

    it "accepts optional suffix context" do
      parent = described_class.new(0)
      child = described_class.new(1, parent)

      expect(child.suffix).to eq(parent)
    end

    it "inherits from PPMd7::Context" do
      expect(described_class.ancestors).to include(
        Omnizip::Algorithms::PPMd7::Context,
      )
    end
  end

  describe "#add_symbol" do
    it "adds new symbol to context" do
      context = described_class.new(0)

      state = context.add_symbol(65) # 'A'

      expect(state).to be_a(Omnizip::Algorithms::PPMd7::SymbolState)
      expect(state.symbol).to eq(65)
      expect(state.freq).to eq(1)
    end

    it "updates sum frequency" do
      context = described_class.new(0)

      context.add_symbol(65)

      expect(context.sum_freq).to eq(1)
    end

    it "raises error for duplicate symbol" do
      context = described_class.new(0)
      context.add_symbol(65)

      expect do
        context.add_symbol(65)
      end.to raise_error(ArgumentError, /already exists/)
    end
  end

  describe "#update_symbol" do
    it "increases symbol frequency" do
      context = described_class.new(0)
      context.add_symbol(65, 5)

      context.update_symbol(65, 3)

      state = context.find_symbol(65)
      expect(state.freq).to eq(8)
    end

    it "updates sum frequency" do
      context = described_class.new(0)
      context.add_symbol(65, 5)
      initial_sum = context.sum_freq

      context.update_symbol(65, 3)

      expect(context.sum_freq).to eq(initial_sum + 3)
    end

    it "triggers rescaling at threshold" do
      context = described_class.new(0)
      context.add_symbol(65, 120)

      # Update should trigger rescaling at 124
      context.update_symbol(65, 5)

      # Frequency should be rescaled down
      state = context.find_symbol(65)
      expect(state.freq).to be < 125
    end

    it "does nothing for non-existent symbol" do
      context = described_class.new(0)

      expect do
        context.update_symbol(65, 3)
      end.not_to raise_error

      expect(context.find_symbol(65)).to be_nil
    end
  end

  describe "#find_symbol" do
    it "finds existing symbol" do
      context = described_class.new(0)
      context.add_symbol(65)

      state = context.find_symbol(65)

      expect(state).not_to be_nil
      expect(state.symbol).to eq(65)
    end

    it "returns nil for non-existent symbol" do
      context = described_class.new(0)

      expect(context.find_symbol(65)).to be_nil
    end
  end

  describe "#total_freq" do
    it "includes escape frequency" do
      context = described_class.new(0)
      context.add_symbol(65, 10)

      # Total = sum_freq (10) + escape_freq (1)
      expect(context.total_freq).to eq(11)
    end
  end

  describe "#needs_escape?" do
    it "returns true when not all symbols seen" do
      context = described_class.new(0)
      context.add_symbol(65)

      # Only 1 of 256 possible symbols
      expect(context.needs_escape?).to eq(true)
    end

    it "returns false when all symbols seen" do
      context = described_class.new(0)

      # Add all 256 symbols
      256.times { |i| context.add_symbol(i) }

      expect(context.needs_escape?).to eq(false)
    end
  end

  describe "#symbols_by_frequency" do
    it "returns symbols sorted by frequency (descending)" do
      context = described_class.new(0)
      context.add_symbol(65, 10)
      context.add_symbol(66, 5)
      context.add_symbol(67, 15)

      symbols = context.symbols_by_frequency

      expect(symbols).to eq([67, 65, 66])
    end
  end

  describe "#root?" do
    it "returns true for root context" do
      context = described_class.new(-1, nil)

      expect(context.root?).to eq(true)
    end

    it "returns false for non-root context" do
      parent = described_class.new(0)
      child = described_class.new(1, parent)

      expect(child.root?).to eq(false)
    end
  end

  describe "#num_symbols" do
    it "returns number of distinct symbols" do
      context = described_class.new(0)
      context.add_symbol(65)
      context.add_symbol(66)
      context.add_symbol(67)

      expect(context.num_symbols).to eq(3)
    end
  end

  describe "RAR variant H specific behavior" do
    describe "frequency rescaling" do
      it "uses RAR maximum frequency threshold (124)" do
        context = described_class.new(0)
        context.add_symbol(65, 120)

        # Adding 5 more should trigger rescaling at 124
        context.update_symbol(65, 5)

        # After rescaling, frequency should be reduced
        state = context.find_symbol(65)
        expect(state.freq).to be <= 63 # (125 + 1) / 2
      end

      it "maintains minimum frequency of 1 after rescaling" do
        context = described_class.new(0)
        context.add_symbol(65, 1)
        context.add_symbol(66, 123)

        # Trigger rescaling
        context.update_symbol(66, 1)

        # Symbol with freq=1 should stay at 1
        state1 = context.find_symbol(65)
        expect(state1.freq).to eq(1)
      end

      it "rescales all symbols proportionally" do
        context = described_class.new(0)
        context.add_symbol(65, 100)
        context.add_symbol(66, 24)

        # Trigger rescaling (sum = 124, next update triggers it)
        context.update_symbol(65, 1)

        # Both should be rescaled
        state1 = context.find_symbol(65)
        state2 = context.find_symbol(66)

        expect(state1.freq).to be < 100
        expect(state2.freq).to be < 24
      end
    end

    describe "escape frequency" do
      it "uses RAR initial escape frequency constant" do
        context = described_class.new(0)

        # RAR_INIT_ESCAPE_FREQ = 1
        expect(context.escape_freq).to eq(1)
      end
    end
  end

  describe "integration with PPMd7::Context" do
    it "inherits all base functionality" do
      context = described_class.new(0)

      # Test inherited methods work
      expect(context).to respond_to(:add_symbol)
      expect(context).to respond_to(:update_symbol)
      expect(context).to respond_to(:find_symbol)
      expect(context).to respond_to(:total_freq)
      expect(context).to respond_to(:needs_escape?)
    end

    it "maintains context tree structure" do
      root = described_class.new(-1)
      level1 = described_class.new(0, root)
      level2 = described_class.new(1, level1)

      expect(level2.suffix).to eq(level1)
      expect(level1.suffix).to eq(root)
      expect(root.suffix).to be_nil
    end
  end
end

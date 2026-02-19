# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::LZMAState do
  describe "#initialize" do
    it "initializes with state 0 and default reps" do
      state = described_class.new
      expect(state.value).to eq(0)
      expect(state.reps).to eq([0, 0, 0, 0]) # XZ Utils: coder->rep0 = 0
    end

    it "accepts custom initial state" do
      state = described_class.new(5)
      expect(state.value).to eq(5)
    end
  end

  describe "#update_literal!" do
    it "transitions state correctly after literal" do
      state = described_class.new(0)
      state.update_literal!
      expect(state.value).to eq(0) # State 0 -> 0
    end

    it "does not modify reps after literal" do
      state = described_class.new(0)
      state.reps[0] = 100
      state.update_literal!
      expect(state.reps[0]).to eq(100)
    end
  end

  describe "#update_match!" do
    it "transitions state and rotates reps after match" do
      state = described_class.new(0)
      state.update_match!(50)
      expect(state.value).to eq(7) # State 0 -> 7
      expect(state.reps).to eq([50, 0, 0, 0]) # XZ Utils: initialized to [0,0,0,0]
    end

    it "rotates all reps correctly" do
      state = described_class.new(7)
      state.instance_variable_set(:@reps, [10, 20, 30, 40])
      state.update_match!(50)
      expect(state.reps).to eq([50, 10, 20, 30])
    end
  end

  describe "#update_rep!" do
    it "transitions state after rep match" do
      state = described_class.new(7)
      state.update_rep!(0)
      expect(state.value).to eq(11) # State 7 -> 11
    end

    it "uses rep0 without rotation for rep index 0" do
      state = described_class.new(7)
      state.instance_variable_set(:@reps, [10, 20, 30, 40])
      state.update_rep!(0)
      expect(state.reps).to eq([10, 20, 30, 40]) # Unchanged
    end

    it "rotates rep1 to rep0 for rep index 1" do
      state = described_class.new(7)
      state.instance_variable_set(:@reps, [10, 20, 30, 40])
      state.update_rep!(1)
      expect(state.reps).to eq([20, 10, 30, 40])
    end
  end

  describe "#use_matched_literal?" do
    it "returns true for states 7-10" do
      state = described_class.new(7)
      expect(state.use_matched_literal?).to be true
    end

    it "returns false for other states" do
      state = described_class.new(0)
      expect(state.use_matched_literal?).to be false
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::XzState do
  let(:state) { described_class.new }

  describe "#initialize" do
    it "starts at STATE_LIT_LIT by default" do
      expect(state.value).to eq(described_class::STATE_LIT_LIT)
    end

    it "accepts initial state" do
      custom_state = described_class.new(described_class::STATE_MATCH_LIT)
      expect(custom_state.value).to eq(described_class::STATE_MATCH_LIT)
    end
  end

  describe "#update_literal" do
    it "transitions STATE_LIT_LIT → STATE_LIT_LIT" do
      state.value = described_class::STATE_LIT_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_LIT_LIT)
    end

    it "transitions STATE_MATCH_LIT_LIT → STATE_LIT_LIT" do
      state.value = described_class::STATE_MATCH_LIT_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_LIT_LIT)
    end

    it "transitions STATE_REP_LIT_LIT → STATE_LIT_LIT" do
      state.value = described_class::STATE_REP_LIT_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_LIT_LIT)
    end

    it "transitions STATE_SHORTREP_LIT_LIT → STATE_LIT_LIT" do
      state.value = described_class::STATE_SHORTREP_LIT_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_LIT_LIT)
    end

    it "transitions STATE_MATCH_LIT → STATE_LIT_LIT (state - 3)" do
      state.value = described_class::STATE_MATCH_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT_LIT)
    end

    it "transitions STATE_REP_LIT → STATE_REP_LIT_LIT (state - 3)" do
      state.value = described_class::STATE_REP_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_REP_LIT_LIT)
    end

    it "transitions STATE_SHORTREP_LIT → STATE_SHORTREP_LIT_LIT (state - 3)" do
      state.value = described_class::STATE_SHORTREP_LIT
      state.update_literal
      expect(state.value).to eq(described_class::STATE_SHORTREP_LIT_LIT)
    end

    it "transitions STATE_LIT_MATCH → STATE_MATCH_LIT (state - 6)" do
      state.value = described_class::STATE_LIT_MATCH
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT)
    end

    it "transitions STATE_LIT_LONGREP → STATE_REP_LIT (state - 6)" do
      state.value = described_class::STATE_LIT_LONGREP
      state.update_literal
      expect(state.value).to eq(described_class::STATE_REP_LIT)
    end

    it "transitions STATE_LIT_SHORTREP → STATE_SHORTREP_LIT (state - 6)" do
      state.value = described_class::STATE_LIT_SHORTREP
      state.update_literal
      expect(state.value).to eq(described_class::STATE_SHORTREP_LIT)
    end

    it "transitions STATE_NONLIT_MATCH → STATE_MATCH_LIT (state - 6)" do
      state.value = described_class::STATE_NONLIT_MATCH
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT)
    end

    it "transitions STATE_NONLIT_REP → STATE_REP_LIT (state - 6)" do
      state.value = described_class::STATE_NONLIT_REP
      state.update_literal
      expect(state.value).to eq(described_class::STATE_REP_LIT)
    end
  end

  describe "#update_match" do
    it "transitions literal states (0-6) to STATE_LIT_MATCH" do
      (0..6).each do |s|
        state.value = s
        state.update_match
        expect(state.value).to eq(described_class::STATE_LIT_MATCH)
      end
    end

    it "transitions non-literal states (7-11) to STATE_NONLIT_MATCH" do
      (7..11).each do |s|
        state.value = s
        state.update_match
        expect(state.value).to eq(described_class::STATE_NONLIT_MATCH)
      end
    end
  end

  describe "#update_long_rep" do
    it "transitions literal states (0-6) to STATE_LIT_LONGREP" do
      (0..6).each do |s|
        state.value = s
        state.update_long_rep
        expect(state.value).to eq(described_class::STATE_LIT_LONGREP)
      end
    end

    it "transitions non-literal states (7-11) to STATE_NONLIT_REP" do
      (7..11).each do |s|
        state.value = s
        state.update_long_rep
        expect(state.value).to eq(described_class::STATE_NONLIT_REP)
      end
    end
  end

  describe "#update_short_rep" do
    it "transitions literal states (0-6) to STATE_LIT_SHORTREP" do
      (0..6).each do |s|
        state.value = s
        state.update_short_rep
        expect(state.value).to eq(described_class::STATE_LIT_SHORTREP)
      end
    end

    it "transitions non-literal states (7-11) to STATE_NONLIT_REP" do
      (7..11).each do |s|
        state.value = s
        state.update_short_rep
        expect(state.value).to eq(described_class::STATE_NONLIT_REP)
      end
    end
  end

  describe "#literal_state?" do
    it "returns true for literal states (0-6)" do
      (0..6).each do |s|
        state.value = s
        expect(state.literal_state?).to be true
      end
    end

    it "returns false for non-literal states (7-11)" do
      (7..11).each do |s|
        state.value = s
        expect(state.literal_state?).to be false
      end
    end
  end

  describe "#dup" do
    it "creates a copy with same value" do
      state.value = described_class::STATE_MATCH_LIT
      copy = state.dup
      expect(copy.value).to eq(described_class::STATE_MATCH_LIT)
    end

    it "creates independent copy" do
      state.value = described_class::STATE_MATCH_LIT
      copy = state.dup
      copy.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT)
      expect(copy.value).to eq(described_class::STATE_MATCH_LIT_LIT)
    end
  end

  describe "#reset" do
    it "resets to STATE_LIT_LIT" do
      state.value = described_class::STATE_NONLIT_MATCH
      state.reset
      expect(state.value).to eq(described_class::STATE_LIT_LIT)
    end
  end

  describe "#valid?" do
    it "returns true for valid states (0-11)" do
      (0..11).each do |s|
        state.value = s
        expect(state.valid?).to be true
      end
    end

    it "returns false for invalid states" do
      state.value = -1
      expect(state.valid?).to be false

      state.value = 12
      expect(state.valid?).to be false

      state.value = 100
      expect(state.valid?).to be false
    end
  end

  describe "#to_s" do
    it "returns state name for valid states" do
      state.value = described_class::STATE_LIT_LIT
      expect(state.to_s).to eq("STATE_LIT_LIT")

      state.value = described_class::STATE_NONLIT_REP
      expect(state.to_s).to eq("STATE_NONLIT_REP")
    end

    it "returns INVALID for invalid states" do
      state.value = 99
      expect(state.to_s).to eq("INVALID(99)")
    end
  end

  describe "encoding sequence simulation" do
    it "handles literal → match → literal sequence" do
      state.value = described_class::STATE_LIT_LIT
      state.update_match
      expect(state.value).to eq(described_class::STATE_LIT_MATCH)
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT)
    end

    it "handles literal → long rep → literal sequence" do
      state.value = described_class::STATE_LIT_LIT
      state.update_long_rep
      expect(state.value).to eq(described_class::STATE_LIT_LONGREP)
      state.update_literal
      expect(state.value).to eq(described_class::STATE_REP_LIT)
    end

    it "handles literal → short rep → literal sequence" do
      state.value = described_class::STATE_LIT_LIT
      state.update_short_rep
      expect(state.value).to eq(described_class::STATE_LIT_SHORTREP)
      state.update_literal
      expect(state.value).to eq(described_class::STATE_SHORTREP_LIT)
    end

    it "handles match → match → literal sequence" do
      state.value = described_class::STATE_LIT_MATCH
      state.update_match
      expect(state.value).to eq(described_class::STATE_NONLIT_MATCH)
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT)
    end

    it "handles complex sequence: L → M → L → L → SR" do
      state.value = described_class::STATE_LIT_LIT
      state.update_match
      expect(state.value).to eq(described_class::STATE_LIT_MATCH)
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT)
      state.update_literal
      expect(state.value).to eq(described_class::STATE_MATCH_LIT_LIT)
      state.update_short_rep
      expect(state.value).to eq(described_class::STATE_LIT_SHORTREP)
    end
  end
end

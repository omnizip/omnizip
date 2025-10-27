# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::State do
  let(:state) { described_class.new }

  describe "#initialize" do
    it "starts at state 0" do
      expect(state.index).to eq(0)
    end
  end

  describe "#update_literal" do
    it "transitions from state 0 correctly" do
      state.update_literal
      expect(state.index).to eq(0)
    end

    it "transitions from state 7 correctly" do
      7.times { state.update_match }
      state.update_literal
      expect(state.index).to eq(4)
    end
  end

  describe "#update_match" do
    it "transitions from state 0 correctly" do
      state.update_match
      expect(state.index).to eq(7)
    end
  end

  describe "#update_rep" do
    it "transitions from state 0 correctly" do
      state.update_rep
      expect(state.index).to eq(8)
    end
  end

  describe "#literal?" do
    it "returns true for states 0-6" do
      expect(state.literal?).to be true
    end

    it "returns false for state 7+" do
      7.times { state.update_match }
      expect(state.literal?).to be false
    end
  end

  describe "#match?" do
    it "returns false for states 0-6" do
      expect(state.match?).to be false
    end

    it "returns true for state 7+" do
      7.times { state.update_match }
      expect(state.match?).to be true
    end
  end

  describe "#reset" do
    it "resets state to 0" do
      state.update_match
      state.reset
      expect(state.index).to eq(0)
    end
  end
end

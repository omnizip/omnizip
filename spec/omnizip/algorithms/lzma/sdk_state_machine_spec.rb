# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Implementations::SevenZip::LZMA::StateMachine do
  let(:state) { described_class.new }

  describe "#initialize" do
    it "starts at state 0" do
      expect(state.index).to eq(0)
    end

    it "is a character state initially" do
      expect(state.is_char_state?).to be true
    end
  end

  describe "#is_char_state?" do
    context "for literal states (0-6)" do
      (0..6).each do |i|
        it "returns true for state #{i}" do
          test_state = described_class.new(i)
          expect(test_state.is_char_state?).to be true
        end
      end
    end

    context "for match/rep states (7-11)" do
      (7..11).each do |i|
        it "returns false for state #{i}" do
          test_state = described_class.new(i)
          expect(test_state.is_char_state?).to be false
        end
      end
    end
  end

  describe "#literal_state" do
    it "maps state 0 to literal state 0" do
      test_state = described_class.new(0)
      expect(test_state.literal_state).to eq(0)
    end

    it "maps state 1 to literal state 1" do
      test_state = described_class.new(1)
      expect(test_state.literal_state).to eq(1)
    end

    it "maps state 2 to literal state 2" do
      test_state = described_class.new(2)
      expect(test_state.literal_state).to eq(2)
    end

    it "maps state 3 to literal state 3" do
      test_state = described_class.new(3)
      expect(test_state.literal_state).to eq(3)
    end

    it "maps state 4 to literal state 1" do
      test_state = described_class.new(4)
      expect(test_state.literal_state).to eq(1)
    end

    it "maps state 5 to literal state 2" do
      test_state = described_class.new(5)
      expect(test_state.literal_state).to eq(2)
    end

    it "maps state 6 to literal state 3" do
      test_state = described_class.new(6)
      expect(test_state.literal_state).to eq(3)
    end

    it "maps state 7 to literal state 4" do
      test_state = described_class.new(7)
      expect(test_state.literal_state).to eq(4)
    end

    it "maps state 8 to literal state 5" do
      test_state = described_class.new(8)
      expect(test_state.literal_state).to eq(5)
    end

    it "maps state 9 to literal state 6" do
      test_state = described_class.new(9)
      expect(test_state.literal_state).to eq(6)
    end

    it "maps state 10 to literal state 4" do
      test_state = described_class.new(10)
      expect(test_state.literal_state).to eq(4)
    end

    it "maps state 11 to literal state 5" do
      test_state = described_class.new(11)
      expect(test_state.literal_state).to eq(5)
    end
  end

  describe "#use_matched_literal?" do
    context "for literal states (0-6)" do
      (0..6).each do |i|
        it "returns false for state #{i}" do
          test_state = described_class.new(i)
          expect(test_state.use_matched_literal?).to be false
        end
      end
    end

    context "for match/rep states (7-11)" do
      (7..11).each do |i|
        it "returns true for state #{i}" do
          test_state = described_class.new(i)
          expect(test_state.use_matched_literal?).to be true
        end
      end
    end
  end

  describe "#category" do
    it "returns :literal for state 0" do
      expect(state.category).to eq(:literal)
    end

    it "returns :literal for state 6" do
      test_state = described_class.new(6)
      expect(test_state.category).to eq(:literal)
    end

    it "returns :match for state 7" do
      test_state = described_class.new(7)
      expect(test_state.category).to eq(:match)
    end

    it "returns :rep for state 8" do
      test_state = described_class.new(8)
      expect(test_state.category).to eq(:rep)
    end

    it "returns :short_rep for state 9" do
      test_state = described_class.new(9)
      expect(test_state.category).to eq(:short_rep)
    end

    it "returns :match for state 10" do
      test_state = described_class.new(10)
      expect(test_state.category).to eq(:match)
    end

    it "returns :rep for state 11" do
      test_state = described_class.new(11)
      expect(test_state.category).to eq(:rep)
    end
  end

  describe "#would_use_matched_literal?" do
    it "returns true when state 0 would transition to matched literal after match" do
      expect(state.would_use_matched_literal?).to be true
    end

    it "returns false for states that remain in char state after match" do
      test_state = described_class.new(7)
      expect(test_state.would_use_matched_literal?).to be true
    end
  end

  describe "#dup" do
    it "creates a copy with the same state" do
      state.update_match
      copy = state.dup
      expect(copy.index).to eq(state.index)
    end

    it "creates an independent copy" do
      copy = state.dup
      copy.update_match
      expect(state.index).to eq(0)
      expect(copy.index).to eq(7)
    end

    it "returns SdkStateMachine instance" do
      copy = state.dup
      expect(copy).to be_a(described_class)
    end
  end

  describe "state transitions" do
    it "transitions correctly after literal from state 0" do
      state.update_literal
      expect(state.index).to eq(0)
      expect(state.is_char_state?).to be true
    end

    it "transitions correctly after match from state 0" do
      state.update_match
      expect(state.index).to eq(7)
      expect(state.use_matched_literal?).to be true
    end

    it "transitions correctly after rep from state 0" do
      state.update_rep
      expect(state.index).to eq(8)
      expect(state.use_matched_literal?).to be true
    end

    it "transitions correctly after short rep from state 0" do
      state.update_short_rep
      expect(state.index).to eq(9)
      expect(state.use_matched_literal?).to be true
    end
  end

  describe "SDK encoding scenarios" do
    it "handles literal → literal sequence" do
      state.update_literal
      expect(state.literal_state).to eq(0)
      expect(state.use_matched_literal?).to be false
    end

    it "handles literal → match → literal sequence" do
      state.update_match
      expect(state.index).to eq(7)
      expect(state.use_matched_literal?).to be true
      state.update_literal
      expect(state.index).to eq(4)
      expect(state.use_matched_literal?).to be false
    end

    it "handles match → match sequence" do
      state.update_match
      state.update_match
      expect(state.index).to eq(10)
      expect(state.use_matched_literal?).to be true
    end

    it "handles complex encoding sequence" do
      # Literal (state 0)
      state.update_literal
      expect(state.index).to eq(0)

      # Match (0 → 7)
      state.update_match
      expect(state.index).to eq(7)
      expect(state.literal_state).to eq(4)

      # Literal (7 → 4)
      state.update_literal
      expect(state.index).to eq(4)
      expect(state.literal_state).to eq(1)

      # Rep (4 → 8)
      state.update_rep
      expect(state.index).to eq(8)
      expect(state.literal_state).to eq(5)
    end
  end
end

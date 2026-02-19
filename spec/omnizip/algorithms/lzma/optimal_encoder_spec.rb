# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::OptimalEncoder do
  # UINT32_MAX is used to indicate literal encoding (no match)
  UINT32_MAX = 0xFFFFFFFF

  describe "#initialize" do
    it "initializes with mode" do
      encoder = described_class.new(mode: :fast)
      expect(encoder.mode).to eq(:fast)
    end
  end

  describe "#find_optimal" do
    # NOTE: Match encoding is tested via integration tests in lzma_integration_spec.rb
    # and lzma_sdk_compat_spec.rb since mocking the optimal encoder is complex.
    # The optimal encoder is exercised through full encoding/decoding round-trips.

    it "returns literal encoding when no valid match exists" do
      encoder = described_class.new(mode: :fast)
      state = Omnizip::Algorithms::LZMA::LZMAState.new
      models = Omnizip::Algorithms::LZMA::ProbabilityModels.new
      dict = Omnizip::Algorithms::LZMA::Dictionary.new(4096)
      match_finder = Omnizip::Algorithms::LZMA::MatchFinder.new(dict)

      # Mock longest_match to return nil (no match found)
      allow(match_finder).to receive(:longest_match).and_return(nil)

      back, length = encoder.find_optimal(0, match_finder, state, [1, 1, 1, 1],
                                          models)

      # Should return literal encoding [UINT32_MAX, 1]
      # XZ Utils compatibility: UINT32_MAX indicates literal encoding
      expect(back).to eq(UINT32_MAX)
      expect(length).to eq(1)
    end

    it "raises error for invalid mode" do
      encoder = described_class.new(mode: :invalid)
      state = Omnizip::Algorithms::LZMA::LZMAState.new
      models = Omnizip::Algorithms::LZMA::ProbabilityModels.new
      dict = Omnizip::Algorithms::LZMA::Dictionary.new(4096)
      match_finder = Omnizip::Algorithms::LZMA::MatchFinder.new(dict)

      expect do
        encoder.find_optimal(0, match_finder, state, [1, 1, 1, 1], models)
      end.to raise_error(ArgumentError, "Unknown mode: invalid")
    end
  end
end

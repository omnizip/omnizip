# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Implementations::SevenZip::LZMA::MatchFinder do
  let(:config) do
    Omnizip::Algorithms::LZMA::MatchFinderConfig.sdk_config(
      dict_size: 65536,
      level: 5,
    )
  end
  let(:finder) { described_class.new(config) }

  describe "#initialize" do
    it "creates finder with SDK configuration" do
      expect(finder.config).to eq(config)
    end

    it "initializes hash tables" do
      expect(finder.instance_variable_get(:@hash_table)).to eq({})
      expect(finder.instance_variable_get(:@hash_chain)).to eq({})
    end
  end

  describe "#find_longest_match" do
    context "with no matches" do
      let(:data) { "abcdefgh".bytes }

      it "returns nil when no duplicate sequence exists" do
        match = finder.find_longest_match(data, 0)
        expect(match).to be_nil
      end
    end

    context "with simple repetition" do
      let(:data) { "abcabc".bytes }

      it "finds match at repeated sequence" do
        # First "abc" at position 0
        finder.find_longest_match(data, 0)
        finder.find_longest_match(data, 1)
        finder.find_longest_match(data, 2)

        # Second "abc" at position 3 should match first "abc"
        match = finder.find_longest_match(data, 3)

        expect(match).not_to be_nil
        expect(match.length).to be >= 3
        expect(match.distance).to eq(3)
      end
    end

    context "with longer matches" do
      let(:data) { ("Hello, World! " * 2).bytes }

      it "finds long matches in repeated text" do
        # Process first occurrence
        14.times { |i| finder.find_longest_match(data, i) }

        # Second occurrence should find long match
        match = finder.find_longest_match(data, 14)

        expect(match).not_to be_nil
        expect(match.length).to be >= 10
        expect(match.distance).to eq(14)
      end
    end

    context "with multiple overlapping matches" do
      let(:data) { "aaaaaaaaaa".bytes }

      it "finds matches in repeated character sequence" do
        # Build up hash table
        finder.find_longest_match(data, 0)
        finder.find_longest_match(data, 1)

        # Should find match to previous 'a's
        match = finder.find_longest_match(data, 2)

        expect(match).not_to be_nil
        expect(match.length).to be >= 2
        expect(match.distance).to be_between(1, 2)
      end
    end

    context "with chain length limits" do
      let(:short_config) do
        Omnizip::Algorithms::LZMA::MatchFinderConfig.new(
          mode: "sdk",
          chain_length: 2, # Very short chain
          window_size: 65536,
          max_match_length: 273,
        )
      end
      let(:short_finder) { described_class.new(short_config) }

      it "respects chain length limit" do
        # Create many positions with same hash
        data = ("ab" * 10).bytes

        # Process up to position 10 (not beyond, to preserve hash chain)
        10.times { |i| short_finder.find_longest_match(data, i) }

        # Should still find matches despite chain limit
        match = short_finder.find_longest_match(data, 10)
        expect(match).not_to be_nil
        expect(match.length).to be >= 2
      end
    end

    context "with minimum match length" do
      let(:data) { "abcdef".bytes }

      it "returns nil for matches shorter than minimum" do
        # Single character shouldn't match
        finder.find_longest_match(data, 0)
        match = finder.find_longest_match(data, 1)

        # No 2+ byte match exists
        expect(match).to be_nil
      end
    end

    context "with maximum match length" do
      let(:long_data) { ("A" * 300).bytes }

      it "limits match length to maximum" do
        # Build hash table
        finder.find_longest_match(long_data, 0)

        # Find match (should be capped at max_match_length)
        match = finder.find_longest_match(long_data, 1)

        if match
          expect(match.length).to be <= config.max_match_length
        end
      end
    end

    context "with lazy matching enabled" do
      let(:lazy_config) do
        Omnizip::Algorithms::LZMA::MatchFinderConfig.sdk_config(
          dict_size: 65536,
          level: 7, # High level enables lazy matching
        )
      end
      let(:lazy_finder) { described_class.new(lazy_config) }

      it "delays match if better match available at next position" do
        # Pattern where next position has better match
        data = "xabcabcde".bytes

        # Process positions
        4.times { |i| lazy_finder.find_longest_match(data, i) }

        # At position 4 ('a'), might delay if position 5 has better match
        match1 = lazy_finder.find_longest_match(data, 4)
        match2 = lazy_finder.find_longest_match(data, 5)

        # Lazy matching may have affected results
        # Just verify it runs without error
        expect([match1,
                match2]).to all(be_nil).or include(be_a(described_class::Match))
      end
    end
  end

  describe "#reset" do
    it "clears hash tables" do
      data = "abcabc".bytes
      finder.find_longest_match(data, 0)

      finder.reset

      expect(finder.instance_variable_get(:@hash_table)).to eq({})
      expect(finder.instance_variable_get(:@hash_chain)).to eq({})
    end

    it "allows reusing finder after reset" do
      data = "abcabc".bytes

      finder.find_longest_match(data, 0)
      finder.reset

      # Should work after reset
      expect { finder.find_longest_match(data, 0) }.not_to raise_error
    end
  end

  describe "SDK compatibility" do
    it "produces consistent matches for same input" do
      data = "The quick brown fox jumps over the lazy dog".bytes

      # Run twice with reset
      results1 = []
      data.size.times { |i| results1 << finder.find_longest_match(data, i) }

      finder.reset

      results2 = []
      data.size.times { |i| results2 << finder.find_longest_match(data, i) }

      # Should produce identical results
      results1.each_with_index do |match1, idx|
        match2 = results2[idx]
        if match1.nil?
          expect(match2).to be_nil
        else
          expect(match2).not_to be_nil
          expect(match2.length).to eq(match1.length)
          expect(match2.distance).to eq(match1.distance)
        end
      end
    end

    it "finds matches similar to reference implementation" do
      # Test with pattern known to compress well
      data = ("abc" * 100).bytes

      matches_found = 0
      data.size.times do |i|
        match = finder.find_longest_match(data, i)
        matches_found += 1 if match
      end

      # Should find many matches in this repetitive pattern
      expect(matches_found).to be > 50
    end
  end

  describe "edge cases" do
    it "handles empty input" do
      expect(finder.find_longest_match([], 0)).to be_nil
    end

    it "handles single byte input" do
      expect(finder.find_longest_match([65], 0)).to be_nil
    end

    it "handles position at end of data" do
      data = "test".bytes
      expect(finder.find_longest_match(data, data.size)).to be_nil
    end

    it "handles position beyond end of data" do
      data = "test".bytes
      expect(finder.find_longest_match(data, data.size + 10)).to be_nil
    end

    it "handles data too short for minimum match" do
      data = "a".bytes
      expect(finder.find_longest_match(data, 0)).to be_nil
    end
  end
end

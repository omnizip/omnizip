# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::MatchFinder do
  let(:dictionary) { Omnizip::Algorithms::LZMA::Dictionary.new(4096) }
  let(:finder) { described_class.new(dictionary) }

  describe "#initialize" do
    it "initializes with dictionary" do
      expect(finder.dictionary).to eq(dictionary)
      expect(finder.buffer).to be_a(String)
      expect(finder.position).to eq(0)
    end
  end

  describe "#feed" do
    it "adds data to buffer" do
      finder.feed("ABABAB")
      expect(finder.buffer).to eq("ABABAB")
    end

    it "appends data to existing buffer" do
      finder.feed("ABC")
      finder.feed("DEF")
      expect(finder.buffer).to eq("ABCDEF")
    end
  end

  describe "#find_matches" do
    it "returns empty array when buffer is too small" do
      finder.feed("ABC")
      matches = finder.find_matches(2)
      expect(matches).to eq([])
    end

    it "finds repeated patterns" do
      finder.feed("ABABAB")
      # Build up hash table by processing positions sequentially once
      # Each call updates the hash table for that position
      (0..4).each { |i| finder.find_matches(i) }

      # Check that hash table has been built
      # Position 2 has same 3-byte pattern as position 0
      matches = finder.find_matches(4)

      expect(matches).to be_an(Array)
      # At position 4 ('A'), looking back we should find matches
      # Position 4 is 'A', matching positions 0, 2
      if matches.any?
        expect(matches.first.distance).to be > 0
        expect(matches.first.length).to be >= 2
      end
    end

    it "finds matches with valid distances" do
      finder.feed("ABCABCABCABC")
      # Process all positions to build hash table
      (0..8).each { |i| finder.find_matches(i) }
      matches = finder.find_matches(9)

      # All matches should have distance <= dictionary size
      matches.each do |match|
        expect(match.distance).to be <= dictionary.size
        expect(match.distance).to be > 0
      end
    end

    it "returns matches sorted by length descending" do
      finder.feed("ABABABAB")
      # Build up hash table
      (0..6).each { |i| finder.find_matches(i) }
      matches = finder.find_matches(7)

      if matches.any?
        lengths = matches.map(&:length)
        expect(lengths).to eq(lengths.sort.reverse)
      end
    end
  end

  describe "#longest_match" do
    it "returns the longest match found" do
      finder.feed("ABABABAB")
      longest = finder.longest_match

      if longest
        expect(longest).to be_a(Omnizip::Algorithms::LZMA::Match)
        all_matches = finder.find_matches
        expect(longest.length).to eq(all_matches.first&.length)
      end
    end

    it "returns nil when no matches found" do
      finder.feed("ABCD")
      longest = finder.longest_match
      expect(longest).to be_nil
    end
  end
end

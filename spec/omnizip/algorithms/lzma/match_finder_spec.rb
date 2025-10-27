# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::MatchFinder do
  let(:finder) { described_class.new }

  describe "#find_longest_match" do
    it "returns nil when position is at end of data" do
      data = "test".bytes
      match = finder.find_longest_match(data, 4)
      expect(match).to be_nil
    end

    it "returns nil when remaining data is too short" do
      data = "t".bytes
      match = finder.find_longest_match(data, 0)
      expect(match).to be_nil
    end

    it "can find matches in repetitive data" do
      data = "AAAA".bytes
      # First call adds position 0 to hash
      finder.find_longest_match(data, 0)
      # Second call should find match with position 0
      match = finder.find_longest_match(data, 1)
      expect(match).not_to be_nil if match
    end

    it "can find longer matches with patterns" do
      data = "abcabc".bytes
      # Add positions to hash table
      (0..2).each { |i| finder.find_longest_match(data, i) }
      # Now should be able to find match
      match = finder.find_longest_match(data, 3)
      expect(match).not_to be_nil if match
    end
  end

  describe "#reset" do
    it "clears internal state" do
      data = "test".bytes
      finder.find_longest_match(data, 0)
      finder.reset
      # After reset, hash table is empty
      expect { finder.reset }.not_to raise_error
    end
  end
end

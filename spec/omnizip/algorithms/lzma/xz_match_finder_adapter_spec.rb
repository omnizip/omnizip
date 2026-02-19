# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/omnizip/algorithms/lzma/xz_match_finder_adapter"

RSpec.describe Omnizip::Algorithms::LZMA::XzMatchFinderAdapter do
  let(:adapter) { described_class.new(data) }

  describe "#initialize" do
    let(:data) { "test data" }

    it "initializes with string data" do
      expect(adapter.pos).to eq(0)
      expect(adapter.matches).to be_empty
      expect(adapter.longest_len).to eq(0)
    end

    it "initializes with byte array" do
      adapter = described_class.new(data.bytes)
      expect(adapter.pos).to eq(0)
      expect(adapter.available).to eq(data.size)
    end

    it "accepts custom dictionary size" do
      adapter = described_class.new(data, dict_size: 1 << 20)
      expect(adapter).to be_a(described_class)
    end

    it "accepts custom nice length" do
      adapter = described_class.new(data, nice_len: 64)
      expect(adapter).to be_a(described_class)
    end
  end

  describe "#find_matches" do
    context "with no repetitions" do
      let(:data) { "abcdef" }

      it "finds no matches in unique data" do
        result = adapter.find_matches
        expect(result).to eq(0)
        expect(adapter.matches).to be_empty
        expect(adapter.longest_len).to eq(0)
      end
    end

    context "with simple repetition" do
      let(:data) { "abcabc" }

      it "finds matches for repeated sequence" do
        # Move to position where repetition starts
        adapter.skip(3)
        result = adapter.find_matches

        expect(result).to be >= 3 # At least 3 bytes match
        expect(adapter.matches).not_to be_empty
        expect(adapter.longest_len).to eq(3)

        # Check match structure
        match = adapter.matches.first
        expect(match.len).to eq(3)
        expect(match.dist).to eq(3) # Distance to previous "abc"
      end
    end

    context "with multiple match lengths" do
      let(:data) { "abcdefabcdefgh" }

      it "finds matches of different lengths" do
        adapter.skip(6) # Position at second "abcdef"
        adapter.find_matches

        # Should find matches of varying lengths
        expect(adapter.matches.size).to be > 0
        expect(adapter.longest_len).to eq(6)

        # Matches should be sorted by length
        lengths = adapter.matches.map(&:len)
        expect(lengths).to eq(lengths.sort)
      end
    end

    context "with long repetition" do
      let(:data) { "a" * 100 }

      it "finds long matches" do
        adapter.skip(10)
        adapter.find_matches

        expect(adapter.longest_len).to be >= 32 # Nice length
      end
    end

    context "at end of data" do
      let(:data) { "abc" }

      it "returns 0 when at end of data" do
        adapter.skip(3)
        result = adapter.find_matches
        expect(result).to eq(0)
      end

      it "returns 0 when insufficient data remains" do
        adapter.skip(2) # Only 1 byte left, need min 2
        result = adapter.find_matches
        expect(result).to eq(0)
      end
    end

    context "with dictionary size limit" do
      let(:data) { "abc#{'x' * 10000}abc" }

      it "respects dictionary size limit" do
        adapter_small = described_class.new(data, dict_size: 100)
        adapter_small.skip(10003) # Move to second "abc"

        result = adapter_small.find_matches
        expect(result).to eq(0) # Too far back, outside dictionary
      end

      it "finds match within dictionary" do
        adapter_large = described_class.new(data, dict_size: 20000)
        adapter_large.skip(10003)

        result = adapter_large.find_matches
        expect(result).to be >= 3 # Within dictionary
      end
    end
  end

  describe "#skip" do
    let(:data) { "abcdefghij" }

    it "advances position without finding matches" do
      initial_pos = adapter.pos
      adapter.skip(3)
      expect(adapter.pos).to eq(initial_pos + 3)
    end

    it "skips multiple bytes" do
      adapter.skip(5)
      expect(adapter.pos).to eq(5)
      expect(adapter.current_byte).to eq(data.bytes[5])
    end

    it "handles skipping beyond data" do
      adapter.skip(100)
      # Should stop at data boundary
      expect(adapter.pos).to be <= data.size
    end

    it "updates hash tables during skip" do
      # Skip builds hash table for future matches
      adapter.skip(5)
      # This is internal behavior, just verify no crash
      expect(adapter.pos).to eq(5)
    end
  end

  describe "#move_pos" do
    let(:data) { "test" }

    it "moves position by one byte" do
      initial_pos = adapter.pos
      adapter.move_pos
      expect(adapter.pos).to eq(initial_pos + 1)
    end

    it "can be called multiple times" do
      3.times { adapter.move_pos }
      expect(adapter.pos).to eq(3)
    end
  end

  describe "#available" do
    let(:data) { "12345" }

    it "returns bytes remaining at start" do
      expect(adapter.available).to eq(5)
    end

    it "decreases as position advances" do
      adapter.skip(2)
      expect(adapter.available).to eq(3)
    end

    it "returns 0 at end" do
      adapter.skip(5)
      expect(adapter.available).to eq(0)
    end
  end

  describe "#current_byte" do
    let(:data) { "abc" }

    it "returns byte at current position" do
      expect(adapter.current_byte).to eq(data.bytes[0])
    end

    it "returns different byte after advancing" do
      adapter.move_pos
      expect(adapter.current_byte).to eq(data.bytes[1])
    end

    it "returns nil at end of data" do
      adapter.skip(3)
      expect(adapter.current_byte).to be_nil
    end
  end

  describe "#get_byte" do
    let(:data) { "abcdef" }

    it "gets byte at positive offset" do
      expect(adapter.get_byte(0)).to eq(data.bytes[0])
      expect(adapter.get_byte(1)).to eq(data.bytes[1])
      expect(adapter.get_byte(2)).to eq(data.bytes[2])
    end

    it "gets byte at negative offset" do
      adapter.skip(3)
      expect(adapter.get_byte(-1)).to eq(data.bytes[2])
      expect(adapter.get_byte(-2)).to eq(data.bytes[1])
    end

    it "returns 0 for out of bounds access" do
      expect(adapter.get_byte(-1)).to eq(0)
      expect(adapter.get_byte(100)).to eq(0)
    end
  end

  describe "#reset" do
    let(:data) { "abcabc" }

    it "resets position to start" do
      adapter.skip(3)
      adapter.find_matches
      adapter.reset

      expect(adapter.pos).to eq(0)
      expect(adapter.matches).to be_empty
      expect(adapter.longest_len).to eq(0)
    end

    it "clears internal state" do
      adapter.skip(3)
      adapter.find_matches
      adapter.reset
      adapter.find_matches

      # Should work as if newly initialized
      expect(adapter.matches).to be_empty
    end
  end

  describe "Match struct" do
    it "creates match with length and distance" do
      match = described_class::Match.new(len: 5, dist: 10)
      expect(match.len).to eq(5)
      expect(match.dist).to eq(10)
    end

    it "has string representation" do
      match = described_class::Match.new(len: 5, dist: 10)
      expect(match.to_s).to include("5")
      expect(match.to_s).to include("10")
    end
  end

  describe "integration scenarios" do
    context "typical compression workflow" do
      let(:data) { "Hello World! Hello World!" }

      it "finds matches as position advances" do
        results = []

        # Process each position
        while adapter.available >= 2
          len = adapter.find_matches
          results << {
            pos: adapter.pos,
            longest: len,
            matches: adapter.matches.dup,
          }
          adapter.move_pos
        end

        # Should have found matches where "Hello World!" repeats
        matching_positions = results.select { |r| r[:longest] > 0 }
        expect(matching_positions).not_to be_empty
      end
    end

    context "with nice length threshold" do
      let(:data) { "a" * 100 }

      it "stops searching at nice length" do
        adapter_nice = described_class.new(data, nice_len: 16)
        adapter_nice.skip(50)
        adapter_nice.find_matches

        # Should stop at or near nice length (may exceed slightly)
        expect(adapter_nice.longest_len).to be >= 16
        expect(adapter_nice.longest_len).to be <= 32
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/compression/lz77_huffman/match_finder"

RSpec.describe Omnizip::Formats::Rar::Compression::LZ77Huffman::MatchFinder do
  let(:finder) { described_class.new }

  describe "#initialize" do
    it "creates finder with default parameters" do
      expect(finder.window_size).to eq(32768)
      expect(finder.max_match_length).to eq(257)
    end

    it "accepts custom window size" do
      custom_finder = described_class.new(16384, 128)
      expect(custom_finder.window_size).to eq(16384)
      expect(custom_finder.max_match_length).to eq(128)
    end

    it "limits max_match_length to MAX_MATCH_LENGTH" do
      custom_finder = described_class.new(32768, 500)
      expect(custom_finder.max_match_length).to eq(257)
    end
  end

  describe "#find_match" do
    context "with simple repetition" do
      it "finds exact 3-byte match" do
        data = "ABCABC".bytes
        match = finder.find_match(data, 3)
        expect(match).not_to be_nil
        expect(match.offset).to eq(3)
        expect(match.length).to eq(3)
      end

      it "finds longer match" do
        data = "ABCDEFABCDEF".bytes
        match = finder.find_match(data, 6)
        expect(match).not_to be_nil
        expect(match.offset).to eq(6)
        expect(match.length).to eq(6)
      end

      it "finds match with repetitive pattern" do
        data = "AAAAAAA".bytes
        match = finder.find_match(data, 1)
        expect(match).not_to be_nil
        expect(match.offset).to eq(1)
        expect(match.length).to be >= 3
      end
    end

    context "with no match" do
      it "returns nil for unique data" do
        data = "ABCDEFGHIJ".bytes
        match = finder.find_match(data, 5)
        expect(match).to be_nil
      end

      it "returns nil at end of data" do
        data = "ABCABC".bytes
        match = finder.find_match(data, 6)
        expect(match).to be_nil
      end

      it "returns nil when less than MIN_MATCH_LENGTH remaining" do
        data = "ABCABCXY".bytes
        match = finder.find_match(data, 6)
        expect(match).to be_nil
      end
    end

    context "with multiple candidates" do
      it "finds best (longest) match" do
        data = "ABCDEFABCDE".bytes
        match = finder.find_match(data, 6)
        expect(match).not_to be_nil
        expect(match.length).to eq(5)
      end
    end

    context "with window size limit" do
      it "ignores matches beyond window size" do
        small_finder = described_class.new(8, 257)
        data = "ABCDEF#{'X' * 10}ABCDEF"
        match = small_finder.find_match(data.bytes, 16)
        expect(match).to be_nil
      end
    end

    context "with max match length limit" do
      it "limits match length to max_match_length" do
        limited_finder = described_class.new(32768, 10)
        data = ("A" * 50).bytes
        match = limited_finder.find_match(data, 20)
        expect(match).not_to be_nil
        expect(match.length).to eq(10)
      end
    end

    context "with string data" do
      it "works with string input" do
        data = "HELLO HELLO"
        match = finder.find_match(data, 6)
        expect(match).not_to be_nil
        expect(match.offset).to eq(6)
        expect(match.length).to eq(5)
      end
    end
  end

  describe "#update" do
    it "adds position to hash chains" do
      data = "ABCDEF".bytes
      expect(finder.hash_chain_count).to eq(0)
      finder.update(data, 0)
      expect(finder.hash_chain_count).to eq(1)
    end

    it "does not error at end of data" do
      data = "ABC".bytes
      expect { finder.update(data, 3) }.not_to raise_error
    end
  end

  describe "#reset" do
    it "clears hash chains" do
      data = "ABCDEF".bytes
      finder.update(data, 0)
      finder.update(data, 1)
      expect(finder.hash_chain_count).to be > 0
      finder.reset
      expect(finder.hash_chain_count).to eq(0)
    end
  end

  describe "Match class" do
    it "stores offset and length" do
      match = described_class::Match.new(5, 10)
      expect(match.offset).to eq(5)
      expect(match.length).to eq(10)
    end

    it "supports equality comparison" do
      match1 = described_class::Match.new(5, 10)
      match2 = described_class::Match.new(5, 10)
      match3 = described_class::Match.new(6, 10)
      expect(match1).to eq(match2)
      expect(match1).not_to eq(match3)
    end
  end

  describe "integration scenarios" do
    it "handles text compression scenario" do
      data = "The quick brown fox jumps over the lazy dog. The quick brown fox."
      match = finder.find_match(data.bytes, 45)
      expect(match).not_to be_nil
      expect(match.length).to be >= 10
    end

    it "handles binary data with repetitions" do
      data = [0x01, 0x02, 0x03, 0x04] * 3
      match = finder.find_match(data, 4)
      expect(match).not_to be_nil
      expect(match.length).to eq(8)
    end
  end
end

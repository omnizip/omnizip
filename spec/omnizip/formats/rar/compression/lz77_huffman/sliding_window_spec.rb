# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Compression::LZ77Huffman::SlidingWindow do
  describe "#initialize" do
    it "creates window with default size" do
      window = described_class.new
      expect(window.size).to eq(64 * 1024)
    end

    it "creates window with custom size" do
      window = described_class.new(1024)
      expect(window.size).to eq(1024)
    end

    it "starts at position 0" do
      window = described_class.new
      expect(window.position).to eq(0)
    end

    it "raises error for non-positive size" do
      expect do
        described_class.new(0)
      end.to raise_error(ArgumentError, /must be positive/)
      expect do
        described_class.new(-1)
      end.to raise_error(ArgumentError, /must be positive/)
    end
  end

  describe "#add_byte" do
    let(:window) { described_class.new(8) }

    it "adds byte to window" do
      window.add_byte(65)
      expect(window.position).to eq(1)
    end

    it "advances position after adding" do
      window.add_byte(65)
      window.add_byte(66)
      window.add_byte(67)
      expect(window.position).to eq(3)
    end

    it "wraps around at window size" do
      8.times { |i| window.add_byte(i) }
      expect(window.position).to eq(0)

      window.add_byte(99)
      expect(window.position).to eq(1)
    end

    it "raises error for byte > 255" do
      expect do
        window.add_byte(256)
      end.to raise_error(ArgumentError, /must be 0-255/)
    end

    it "raises error for byte < 0" do
      expect do
        window.add_byte(-1)
      end.to raise_error(ArgumentError, /must be 0-255/)
    end

    it "accepts all valid byte values" do
      expect { window.add_byte(0) }.not_to raise_error
      expect { window.add_byte(255) }.not_to raise_error
    end
  end

  describe "#copy_match" do
    let(:window) { described_class.new(16) }

    before do
      # Fill window with known data: [0, 1, 2, 3, 4, 5, 6, 7, ...]
      10.times { |i| window.add_byte(i) }
    end

    it "copies bytes from backward offset" do
      # Current position is 10
      # Distance 3 means copy from position 7
      # Copy should get bytes [7, 8, 9]
      result = window.copy_match(3, 3)
      expect(result).to eq([7, 8, 9])
    end

    it "handles single byte match" do
      result = window.copy_match(1, 1)
      expect(result).to eq([9])
    end

    it "handles overlapping match" do
      # Distance < length means overlap
      # Distance 2, length 4
      # Copy [8, 9, 8, 9] (repeats)
      result = window.copy_match(2, 4)
      expect(result).to eq([8, 9, 8, 9])
    end

    it "adds copied bytes to window" do
      old_pos = window.position
      window.copy_match(3, 3)
      expect(window.position).to eq((old_pos + 3) % 16)
    end

    it "handles wrap-around correctly" do
      # Fill entire window
      16.times { |i| window.add_byte(i + 10) }
      # Position is now 10 (wrapped from 10 + 16)
      # Distance 12 should get bytes from near beginning
      result = window.copy_match(12, 2)
      expect(result.size).to eq(2)
    end

    it "raises error for distance = 0" do
      expect { window.copy_match(0, 3) }.to raise_error(ArgumentError)
    end

    it "raises error for distance > window size" do
      expect { window.copy_match(17, 3) }.to raise_error(ArgumentError)
    end

    it "raises error for length = 0" do
      expect { window.copy_match(3, 0) }.to raise_error(ArgumentError)
    end

    it "raises error for negative length" do
      expect { window.copy_match(3, -1) }.to raise_error(ArgumentError)
    end
  end

  describe "#get_byte_at_offset" do
    let(:window) { described_class.new(8) }

    before do
      5.times { |i| window.add_byte(i + 10) }
    end

    it "gets byte at backward offset" do
      # Window has [10, 11, 12, 13, 14], position = 5
      # Offset 1 = position 4 = byte 14
      expect(window.get_byte_at_offset(1)).to eq(14)
    end

    it "gets byte at various offsets" do
      expect(window.get_byte_at_offset(1)).to eq(14)
      expect(window.get_byte_at_offset(2)).to eq(13)
      expect(window.get_byte_at_offset(5)).to eq(10)
    end

    it "raises error for offset = 0" do
      expect { window.get_byte_at_offset(0) }.to raise_error(ArgumentError)
    end

    it "raises error for offset > window size" do
      expect { window.get_byte_at_offset(9) }.to raise_error(ArgumentError)
    end
  end

  describe "#reset" do
    let(:window) { described_class.new(8) }

    it "resets position to 0" do
      5.times { |i| window.add_byte(i) }
      window.reset
      expect(window.position).to eq(0)
    end

    it "clears buffer" do
      5.times { |i| window.add_byte(i + 10) }
      window.reset

      # After reset, all bytes should be 0
      expect(window.get_byte_at_offset(1)).to eq(0)
    end

    it "allows reuse after reset" do
      5.times { |i| window.add_byte(i) }
      window.reset

      window.add_byte(99)
      expect(window.position).to eq(1)
      expect(window.get_byte_at_offset(1)).to eq(99)
    end
  end

  describe "integration scenarios" do
    let(:window) { described_class.new(32) }

    it "handles typical LZ77 decode sequence" do
      # Add some literal bytes
      "ABCD".bytes.each { |b| window.add_byte(b) }

      # Copy match (distance 4, length 4) = "ABCD"
      match = window.copy_match(4, 4)
      expect(match).to eq("ABCD".bytes)

      # Position should be 8
      expect(window.position).to eq(8)
    end

    it "handles run-length encoding pattern" do
      # Add single byte
      window.add_byte(65) # 'A'

      # Copy with distance=1, length=10 creates "AAAAAAAAAA"
      result = window.copy_match(1, 10)
      expect(result).to eq([65] * 10)
    end

    it "handles complex overlapping matches" do
      # Pattern: "ABC"
      "ABC".bytes.each { |b| window.add_byte(b) }

      # Match (distance=3, length=6) = "ABCABC"
      result = window.copy_match(3, 6)
      expect(result).to eq("ABCABC".bytes)
    end

    it "maintains correct state after multiple operations" do
      # Add some data
      "HELLO".bytes.each { |b| window.add_byte(b) }

      # Copy match
      window.copy_match(5, 5)

      # Add more data
      "WORLD".bytes.each { |b| window.add_byte(b) }

      # Verify position is correct
      expect(window.position).to eq(15)
    end

    it "handles full window scenario" do
      # Fill entire window
      32.times { |i| window.add_byte(i) }

      # Position should wrap
      expect(window.position).to eq(0)

      # Can still copy matches
      result = window.copy_match(5, 3)
      expect(result.size).to eq(3)
    end
  end
end

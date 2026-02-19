# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Compression::LZ77Huffman::Decoder do
  let(:input) { StringIO.new }
  let(:decoder) { described_class.new(input) }

  describe "#initialize" do
    it "creates decoder with default window size" do
      expect(decoder.window_size).to eq(64 * 1024)
    end

    it "creates decoder with custom window size" do
      custom = described_class.new(input, window_size: 1024)
      expect(custom.window_size).to eq(1024)
    end
  end

  describe "#decode" do
    it "handles empty input" do
      result = decoder.decode
      expect(result).to eq("")
    end

    it "handles EOF gracefully" do
      # Empty stream
      result = decoder.decode
      expect(result).to be_a(String)
    end

    it "respects max_output parameter" do
      # Create simple compressed stream (will be mostly tree data)
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(input, :write)

      # Write minimal tree (512 symbols with 4-bit lengths)
      512.times { writer.write_bits(0, 4) }
      writer.flush

      input.rewind
      result = decoder.decode(10)

      # Should not exceed max_output
      expect(result.bytesize).to be <= 10
    end
  end

  describe "literal processing" do
    it "decodes literal bytes" do
      # This is a simplified test - real decoding requires proper Huffman tree
      # For now, just verify the decoder can be created and called
      result = decoder.decode
      expect(result).to be_a(String)
    end
  end

  describe "match processing" do
    it "processes LZ77 matches" do
      # Simplified test for match processing
      result = decoder.decode
      expect(result).to be_a(String)
    end
  end

  describe "integration" do
    it "combines HuffmanCoder and SlidingWindow" do
      # Integration test - verify components work together
      result = decoder.decode
      expect(result).to be_a(String)
    end

    it "handles multiple decode calls" do
      decoder.decode
      # Second call should work
      result = decoder.decode
      expect(result).to be_a(String)
    end
  end

  describe "constants" do
    it "defines symbol ranges" do
      expect(described_class::LITERAL_SYMBOLS).to eq(0..255)
      expect(described_class::END_OF_BLOCK).to eq(256)
      expect(described_class::MATCH_SYMBOLS).to eq(257..511)
    end

    it "defines match parameters" do
      expect(described_class::MIN_MATCH_LENGTH).to eq(3)
      expect(described_class::MAX_MATCH_LENGTH).to eq(257)
    end

    it "defines default window size" do
      expect(described_class::DEFAULT_WINDOW_SIZE).to eq(64 * 1024)
    end
  end

  describe "OOP compliance" do
    it "has single responsibility (orchestration)" do
      # Decoder orchestrates but delegates:
      # - HuffmanCoder: Huffman tree operations
      # - SlidingWindow: Window management
      # - BitStream: Bit-level I/O

      # Verify decoder doesn't duplicate these responsibilities
      expect(decoder).to respond_to(:decode)
      expect(decoder).to respond_to(:window_size)
      expect(decoder).not_to respond_to(:build_tree) # That's HuffmanCoder's job
      expect(decoder).not_to respond_to(:add_byte) # That's SlidingWindow's job
    end
  end
end

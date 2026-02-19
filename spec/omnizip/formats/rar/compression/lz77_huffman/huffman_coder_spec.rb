# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Compression::LZ77Huffman::HuffmanCoder do
  let(:coder) { described_class.new }

  describe "#initialize" do
    it "creates empty coder" do
      expect(coder.empty?).to be true
    end

    it "has zero symbols initially" do
      expect(coder.symbol_count).to eq(0)
    end
  end

  describe "#build_tree" do
    it "builds tree from simple code lengths" do
      # Simple tree: A=0(1-bit), B=10(2-bit), C=11(2-bit)
      code_lengths = [1, 2, 2]
      coder.build_tree(code_lengths)

      expect(coder.empty?).to be false
      expect(coder.symbol_count).to eq(3)
    end

    it "handles single symbol" do
      code_lengths = [1]
      coder.build_tree(code_lengths)

      expect(coder.symbol_count).to eq(1)
    end

    it "handles empty tree" do
      code_lengths = []
      coder.build_tree(code_lengths)

      expect(coder.empty?).to be true
    end

    it "skips zero-length codes" do
      # Symbol 0: length 2, Symbol 1: unused, Symbol 2: length 2
      code_lengths = [2, 0, 2]
      coder.build_tree(code_lengths)

      # Only 2 symbols with non-zero lengths
      expect(coder.symbol_count).to eq(2)
    end

    it "builds canonical Huffman tree correctly" do
      # Standard canonical Huffman example
      # Lengths: [3, 3, 3, 3, 3, 2, 4, 4]
      code_lengths = [3, 3, 3, 3, 3, 2, 4, 4]
      coder.build_tree(code_lengths)

      expect(coder.symbol_count).to eq(8)
    end
  end

  describe "#decode_symbol" do
    let(:bit_stream) { Omnizip::Formats::Rar::Compression::BitStream.new(io, :read) }
    let(:io) { StringIO.new }

    before do
      # Build simple tree: A=0(1-bit), B=10(2-bit), C=11(2-bit)
      coder.build_tree([1, 2, 2])
    end

    it "decodes symbol with 1-bit code" do
      # Write bit 0 (symbol A)
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      writer.write_bit(0)
      writer.flush

      io.rewind
      symbol = coder.decode_symbol(bit_stream)
      expect(symbol).to eq(0)
    end

    it "decodes symbol with 2-bit code" do
      # Write bits 10 (symbol B)
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      writer.write_bit(1)
      writer.write_bit(0)
      writer.flush

      io.rewind
      symbol = coder.decode_symbol(bit_stream)
      expect(symbol).to eq(1)
    end

    it "decodes multiple symbols correctly" do
      # Write: 0 (A), 10 (B), 11 (C), 0 (A)
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      writer.write_bit(0)
      writer.write_bits(0b10, 2)
      writer.write_bits(0b11, 2)
      writer.write_bit(0)
      writer.flush

      io.rewind
      expect(coder.decode_symbol(bit_stream)).to eq(0) # A
      expect(coder.decode_symbol(bit_stream)).to eq(1) # B
      expect(coder.decode_symbol(bit_stream)).to eq(2) # C
      expect(coder.decode_symbol(bit_stream)).to eq(0) # A
    end

    it "raises EOFError when stream ends mid-decode" do
      # Create empty stream - should raise EOF immediately
      empty_io = StringIO.new("")
      empty_stream = Omnizip::Formats::Rar::Compression::BitStream.new(
        empty_io, :read
      )

      expect { coder.decode_symbol(empty_stream) }.to raise_error(EOFError)
    end
  end

  describe "#parse_tree" do
    let(:bit_stream) { Omnizip::Formats::Rar::Compression::BitStream.new(io, :read) }
    let(:io) { StringIO.new }

    it "parses tree structure from bit stream" do
      # Write code lengths for 4 symbols: [3, 2, 4, 2]
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      writer.write_bits(3, 4) # Symbol 0: length 3
      writer.write_bits(2, 4) # Symbol 1: length 2
      writer.write_bits(4, 4) # Symbol 2: length 4
      writer.write_bits(2, 4) # Symbol 3: length 2
      writer.flush

      io.rewind
      coder.parse_tree(bit_stream, 4)

      expect(coder.symbol_count).to eq(4)
    end

    it "handles empty alphabet" do
      coder.parse_tree(bit_stream, 0)
      expect(coder.empty?).to be true
    end

    it "handles single symbol alphabet" do
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      writer.write_bits(1, 4)
      writer.flush

      io.rewind
      coder.parse_tree(bit_stream, 1)

      expect(coder.symbol_count).to eq(1)
    end
  end

  describe "#encode_symbol" do
    before do
      # Build tree: A=0(1-bit), B=10(2-bit), C=11(2-bit)
      coder.build_tree([1, 2, 2])
    end

    it "returns code and length for valid symbol" do
      code, length = coder.encode_symbol(0)
      expect(code).to eq(0)
      expect(length).to eq(1)
    end

    it "returns correct code for 2-bit symbol" do
      code, length = coder.encode_symbol(1)
      expect(code).to eq(2) # Binary 10
      expect(length).to eq(2)
    end

    it "returns nil for undefined symbol" do
      result = coder.encode_symbol(99)
      expect(result).to be_nil
    end
  end

  describe "#reset" do
    before do
      coder.build_tree([1, 2, 2])
    end

    it "clears the decode table" do
      expect(coder.empty?).to be false

      coder.reset

      expect(coder.empty?).to be true
    end

    it "resets symbol count" do
      expect(coder.symbol_count).to eq(3)

      coder.reset

      expect(coder.symbol_count).to eq(0)
    end

    it "allows building new tree after reset" do
      coder.reset
      coder.build_tree([2, 2])

      expect(coder.symbol_count).to eq(2)
    end
  end

  describe "canonical Huffman properties" do
    it "builds deterministic tree from lengths" do
      code_lengths = [2, 3, 3, 4]

      coder1 = described_class.new
      coder1.build_tree(code_lengths)

      coder2 = described_class.new
      coder2.build_tree(code_lengths)

      # Both should produce same decode table
      expect(coder1.symbol_count).to eq(coder2.symbol_count)
    end

    it "assigns sequential codes for same length" do
      # 3 symbols with length 2: should get codes 00, 01, 10
      code_lengths = [2, 2, 2]
      coder.build_tree(code_lengths)

      code0, len0 = coder.encode_symbol(0)
      code1, len1 = coder.encode_symbol(1)
      code2, len2 = coder.encode_symbol(2)

      expect([len0, len1, len2]).to eq([2, 2, 2])
      expect([code0, code1, code2]).to eq([0, 1, 2])
    end

    it "assigns lower values to shorter codes" do
      # Symbol 0: length 1, Symbol 1: length 2
      code_lengths = [1, 2]
      coder.build_tree(code_lengths)

      code0, len0 = coder.encode_symbol(0)
      code1, len1 = coder.encode_symbol(1)

      expect(len0).to be < len1
      expect(code0).to be < code1
    end
  end

  describe "integration with BitStream" do
    let(:io) { StringIO.new }

    it "round-trips encode and decode" do
      # Build tree
      code_lengths = [2, 2, 3, 3, 3]
      coder.build_tree(code_lengths)

      # Encode symbols
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      [0, 1, 2, 3, 4].each do |sym|
        code, length = coder.encode_symbol(sym)
        writer.write_bits(code, length)
      end
      writer.flush

      # Decode symbols
      io.rewind
      reader = Omnizip::Formats::Rar::Compression::BitStream.new(io, :read)
      decoded = []
      5.times do
        decoded << coder.decode_symbol(reader)
      end

      expect(decoded).to eq([0, 1, 2, 3, 4])
    end

    it "handles alternating symbols" do
      code_lengths = [1, 2, 2]
      coder.build_tree(code_lengths)

      # Encode pattern: 0, 1, 0, 2, 0, 1
      writer = Omnizip::Formats::Rar::Compression::BitStream.new(io, :write)
      symbols = [0, 1, 0, 2, 0, 1]
      symbols.each do |sym|
        code, length = coder.encode_symbol(sym)
        writer.write_bits(code, length)
      end
      writer.flush

      io.rewind
      reader = Omnizip::Formats::Rar::Compression::BitStream.new(io, :read)
      decoded = Array.new(symbols.size) { coder.decode_symbol(reader) }

      expect(decoded).to eq(symbols)
    end
  end
end

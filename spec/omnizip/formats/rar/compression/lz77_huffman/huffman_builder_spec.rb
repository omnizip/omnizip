# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/compression/lz77_huffman/huffman_builder"

RSpec.describe Omnizip::Formats::Rar::Compression::LZ77Huffman::HuffmanBuilder do
  let(:builder) { described_class.new }

  describe "#initialize" do
    it "creates empty builder" do
      expect(builder.empty?).to be true
      expect(builder.symbol_count).to eq(0)
    end
  end

  describe "#add_symbol" do
    it "adds single symbol" do
      builder.add_symbol(65)
      expect(builder.frequencies[65]).to eq(1)
      expect(builder.symbol_count).to eq(1)
    end

    it "adds multiple occurrences" do
      builder.add_symbol(65, 5)
      expect(builder.frequencies[65]).to eq(5)
    end

    it "accumulates frequencies" do
      builder.add_symbol(65)
      builder.add_symbol(65)
      builder.add_symbol(65, 3)
      expect(builder.frequencies[65]).to eq(5)
    end

    it "tracks multiple symbols" do
      builder.add_symbol(65)
      builder.add_symbol(66)
      builder.add_symbol(67)
      expect(builder.symbol_count).to eq(3)
    end
  end

  describe "#build_tree" do
    it "returns nil for empty builder" do
      expect(builder.build_tree).to be_nil
    end

    it "builds single node for one symbol" do
      builder.add_symbol(65)
      root = builder.build_tree
      expect(root).not_to be_nil
      expect(root.leaf?).to be true
      expect(root.symbol).to eq(65)
    end

    it "builds tree for two symbols" do
      builder.add_symbol(65, 3)
      builder.add_symbol(66, 5)
      root = builder.build_tree
      expect(root).not_to be_nil
      expect(root.leaf?).to be false
      expect(root.left).not_to be_nil
      expect(root.right).not_to be_nil
    end

    it "builds balanced tree for equal frequencies" do
      builder.add_symbol(65, 1)
      builder.add_symbol(66, 1)
      builder.add_symbol(67, 1)
      builder.add_symbol(68, 1)
      root = builder.build_tree
      expect(root).not_to be_nil
    end
  end

  describe "#generate_codes" do
    it "returns empty hash for no symbols" do
      expect(builder.generate_codes).to eq({})
    end

    it "generates code for single symbol" do
      builder.add_symbol(65)
      codes = builder.generate_codes
      expect(codes[65]).to eq([0, 1])
    end

    it "generates codes for two symbols" do
      builder.add_symbol(65, 3)
      builder.add_symbol(66, 5)
      codes = builder.generate_codes
      expect(codes.size).to eq(2)
      expect(codes[65][1]).to eq(1)
      expect(codes[66][1]).to eq(1)
    end

    it "assigns shorter codes to more frequent symbols" do
      builder.add_symbol(65, 10)
      builder.add_symbol(66, 1)
      codes = builder.generate_codes
      expect(codes[65][1]).to be <= codes[66][1]
    end

    it "generates canonical codes" do
      builder.add_symbol(65, 5)
      builder.add_symbol(66, 9)
      builder.add_symbol(67, 12)
      builder.add_symbol(68, 13)
      codes = builder.generate_codes

      # Same length codes should be sequential
      same_length_codes = codes.values.group_by { |_, len| len }
      same_length_codes.each_value do |code_list|
        code_values = code_list.map { |code, _| code }.sort
        next if code_values.size == 1

        (1...code_values.size).each do |i|
          expect(code_values[i]).to eq(code_values[i - 1] + 1)
        end
      end
    end
  end

  describe "#code_lengths" do
    it "returns empty for no symbols" do
      expect(builder.code_lengths).to eq({})
    end

    it "returns length 1 for single symbol" do
      builder.add_symbol(65)
      lengths = builder.code_lengths
      expect(lengths[65]).to eq(1)
    end

    it "returns code lengths for multiple symbols" do
      builder.add_symbol(65, 10)
      builder.add_symbol(66, 5)
      builder.add_symbol(67, 2)
      lengths = builder.code_lengths
      expect(lengths.size).to eq(3)
      expect(lengths.values).to all(be_positive)
    end
  end

  describe "#reset" do
    it "clears all frequencies" do
      builder.add_symbol(65)
      builder.add_symbol(66)
      builder.reset
      expect(builder.empty?).to be true
      expect(builder.symbol_count).to eq(0)
    end

    it "allows building new tree after reset" do
      builder.add_symbol(65)
      builder.reset
      builder.add_symbol(66)
      codes = builder.generate_codes
      expect(codes.size).to eq(1)
      expect(codes[66]).not_to be_nil
    end
  end

  describe "Node class" do
    it "creates leaf node" do
      node = described_class::Node.new(65, 10)
      expect(node.symbol).to eq(65)
      expect(node.frequency).to eq(10)
      expect(node.leaf?).to be true
    end

    it "creates internal node" do
      node = described_class::Node.new(nil, 20)
      left = described_class::Node.new(65, 10)
      right = described_class::Node.new(66, 10)
      node.left = left
      node.right = right
      expect(node.leaf?).to be false
    end
  end

  describe "integration scenarios" do
    it "handles text compression scenario" do
      text = "hello world"
      text.each_byte { |b| builder.add_symbol(b) }
      codes = builder.generate_codes
      expect(codes.size).to be > 0
      expect(codes.values).to all(be_an(Array))
    end

    it "handles skewed frequency distribution" do
      builder.add_symbol(65, 100)
      builder.add_symbol(66, 10)
      builder.add_symbol(67, 1)
      codes = builder.generate_codes
      expect(codes[65][1]).to be < codes[67][1]
    end

    it "handles many symbols" do
      (0..255).each { |i| builder.add_symbol(i, i + 1) }
      codes = builder.generate_codes
      expect(codes.size).to eq(256)
    end
  end
end

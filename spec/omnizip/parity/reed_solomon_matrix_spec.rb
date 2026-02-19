# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/reed_solomon_matrix"
require "omnizip/parity/galois16"

RSpec.describe Omnizip::Parity::ReedSolomonMatrix do
  let(:block_size) { 100 }

  describe "#initialize" do
    it "stores indices and parameters" do
      present = [0, 1, 3]
      missing = [2, 4]
      recovery_exponents = [0, 1, 2]
      total = 5

      matrix = described_class.new(present, missing, recovery_exponents, total,
                                   block_size)

      expect(matrix.present_indices).to eq([0, 1, 3])
      expect(matrix.missing_indices).to eq([2, 4])
      expect(matrix.recovery_exponents).to eq([0, 1, 2])
      expect(matrix.total_inputs).to eq(5)
      expect(matrix.block_size).to eq(block_size)
    end

    it "sorts indices" do
      # Provide unsorted indices
      present = [3, 0, 1]
      missing = [4, 2]
      recovery_exponents = [2, 0, 1]

      matrix = described_class.new(present, missing, recovery_exponents, 5,
                                   block_size)

      # Should be sorted
      expect(matrix.present_indices).to eq([0, 1, 3])
      expect(matrix.missing_indices).to eq([2, 4])
      expect(matrix.recovery_exponents).to eq([0, 1, 2])
    end

    it "initializes matrix as nil before compute!" do
      matrix = described_class.new([0], [1], [0], 2, block_size)
      expect(matrix.matrix).to be_nil
      expect(matrix.bases).to be_nil
      expect(matrix.used_recovery_exponents).to be_nil
    end
  end

  describe "#compute!" do
    it "computes matrix coefficients" do
      # Simple case: 1 missing block
      present = [0, 1]
      missing = [2]
      recovery_exponents = [0, 1, 2]

      matrix = described_class.new(present, missing, recovery_exponents, 3,
                                   block_size)
      matrix.compute!

      expect(matrix.matrix).not_to be_nil
      expect(matrix.bases).not_to be_nil
      expect(matrix.used_recovery_exponents).to eq([0]) # Only first exponent needed
    end

    it "selects correct number of recovery exponents" do
      # 2 missing blocks requires 2 recovery exponents
      present = [0, 1]
      missing = [2, 3]
      recovery_exponents = [0, 1, 2, 3, 4]

      matrix = described_class.new(present, missing, recovery_exponents, 4,
                                   block_size)
      matrix.compute!

      expect(matrix.used_recovery_exponents).to eq([0, 1])
    end

    it "creates square matrix matching missing count" do
      present = [0, 1, 2]
      missing = [3, 4]
      recovery_exponents = [0, 1, 2, 3]

      matrix = described_class.new(present, missing, recovery_exponents, 5,
                                   block_size)
      matrix.compute!

      # Matrix should be 2x2 (num_missing x num_missing)
      expect(matrix.matrix.size).to eq(2)
      expect(matrix.matrix[0].size).to eq(2)
      expect(matrix.matrix[1].size).to eq(2)
    end

    it "produces identity when A * A^-1" do
      # Verify Gaussian elimination correctness
      present = [0, 1]
      missing = [2, 3]
      recovery_exponents = [0, 1]

      matrix = described_class.new(present, missing, recovery_exponents, 4,
                                   block_size)
      matrix.compute!

      # Reconstruct A matrix
      bases = matrix.bases
      a_matrix = [
        [
          Omnizip::Parity::Galois16.power(bases[2], 0),
          Omnizip::Parity::Galois16.power(bases[3], 0),
        ],
        [
          Omnizip::Parity::Galois16.power(bases[2], 1),
          Omnizip::Parity::Galois16.power(bases[3], 1),
        ],
      ]

      # Compute A * matrix (which is A^-1 transposed)
      # Need to transpose back for multiplication
      a_inv = matrix.matrix.transpose
      product = multiply_matrices(a_matrix, a_inv)

      # Should be identity matrix
      expect(product[0][0]).to eq(1)
      expect(product[0][1]).to eq(0)
      expect(product[1][0]).to eq(0)
      expect(product[1][1]).to eq(1)
    end
  end

  describe "#coefficient" do
    it "returns matrix coefficients" do
      present = [0]
      missing = [1, 2]
      recovery_exponents = [0, 1]

      matrix = described_class.new(present, missing, recovery_exponents, 3,
                                   block_size)
      matrix.compute!

      # Should have 2x2 matrix
      coef_00 = matrix.coefficient(0, 0)
      coef_01 = matrix.coefficient(0, 1)
      coef_10 = matrix.coefficient(1, 0)
      coef_11 = matrix.coefficient(1, 1)

      expect(coef_00).to be_a(Integer)
      expect(coef_01).to be_a(Integer)
      expect(coef_10).to be_a(Integer)
      expect(coef_11).to be_a(Integer)
    end

    it "raises error if matrix not computed" do
      matrix = described_class.new([0], [1], [0], 2, block_size)

      expect do
        matrix.coefficient(0, 0)
      end.to raise_error(/Matrix not computed/)
    end
  end

  describe "#present_contribution_coefficient" do
    it "computes base^exponent for present blocks" do
      present = [0, 1]
      missing = [2]
      recovery_exponents = [5]

      matrix = described_class.new(present, missing, recovery_exponents, 3,
                                   block_size)
      matrix.compute!

      # For present block 0, exponent 5
      coef = matrix.present_contribution_coefficient(0, 5)
      expected = Omnizip::Parity::Galois16.power(matrix.bases[0], 5)

      expect(coef).to eq(expected)
    end

    it "returns consistent values" do
      present = [0, 1, 2]
      missing = [3]
      recovery_exponents = [7]

      matrix = described_class.new(present, missing, recovery_exponents, 4,
                                   block_size)
      matrix.compute!

      coef1 = matrix.present_contribution_coefficient(1, 7)
      coef2 = matrix.present_contribution_coefficient(1, 7)

      expect(coef1).to eq(coef2)
    end
  end

  describe "#process_chunk" do
    let(:chunk_size) { 4 } # 2 words

    it "performs output ^= input * factor" do
      matrix = described_class.new([0], [1], [0], 2, block_size)
      matrix.compute!

      factor = 7
      input_chunk = "\x05\x00\x0A\x00".b # [5, 10] as 16-bit LE words
      output_block = "\x00" * block_size
      output_block = output_block.dup

      matrix.process_chunk(factor, input_chunk, output_block, chunk_size)

      # Check first two words
      word1 = output_block.getbyte(0) | (output_block.getbyte(1) << 8)
      word2 = output_block.getbyte(2) | (output_block.getbyte(3) << 8)

      expected1 = Omnizip::Parity::Galois16.multiply(5, 7)
      expected2 = Omnizip::Parity::Galois16.multiply(10, 7)

      expect(word1).to eq(expected1)
      expect(word2).to eq(expected2)
    end

    it "accumulates multiple operations (XOR)" do
      matrix = described_class.new([0], [1], [0], 2, block_size)
      matrix.compute!

      factor = 3
      input_chunk = "\x02\x00".b
      output_block = "\u0001\u0000#{"\x00" * 98}"
      output_block = output_block.dup

      # First operation
      matrix.process_chunk(factor, input_chunk, output_block, 2)
      word1 = output_block.getbyte(0) | (output_block.getbyte(1) << 8)

      expected = Omnizip::Parity::Galois16.add(
        1,
        Omnizip::Parity::Galois16.multiply(2, 3),
      )
      expect(word1).to eq(expected)

      # Second operation (XOR twice should cancel)
      matrix.process_chunk(factor, input_chunk, output_block, 2)
      word2 = output_block.getbyte(0) | (output_block.getbyte(1) << 8)

      expect(word2).to eq(1)
    end

    it "respects output_offset parameter" do
      matrix = described_class.new([0], [1], [0], 2, block_size)
      matrix.compute!

      factor = 5
      input_chunk = "\x03\x00".b
      output_block = "\x00" * block_size
      output_block = output_block.dup
      offset = 10

      matrix.process_chunk(factor, input_chunk, output_block, 2,
                           output_offset: offset)

      # Check at offset
      word = output_block.getbyte(offset) | (output_block.getbyte(offset + 1) << 8)
      expected = Omnizip::Parity::Galois16.multiply(3, 5)

      expect(word).to eq(expected)

      # Check beginning is still zero
      word_start = output_block.getbyte(0) | (output_block.getbyte(1) << 8)
      expect(word_start).to eq(0)
    end

    it "skips processing when factor is zero" do
      matrix = described_class.new([0], [1], [0], 2, block_size)
      matrix.compute!

      input_chunk = "\xFF\xFF".b
      output_block = "\u0001\u0000#{"\x00" * 98}"
      original = output_block.dup

      # With factor 0, output should not change
      matrix.process_chunk(0, input_chunk, output_block, 2)

      expect(output_block).to eq(original)
    end

    it "handles little-endian 16-bit words correctly" do
      matrix = described_class.new([0], [1], [0], 2, block_size)
      matrix.compute!

      factor = 2
      # 0x0201 as bytes = 0x0102 as 16-bit LE word = 513
      input_chunk = "\x01\x02".b
      output_block = "\x00" * block_size
      output_block = output_block.dup

      matrix.process_chunk(factor, input_chunk, output_block, 2)

      word = output_block.getbyte(0) | (output_block.getbyte(1) << 8)
      expected = Omnizip::Parity::Galois16.multiply(0x0201, 2)

      expect(word).to eq(expected)
    end
  end

  describe "#recovery_count and #output_count" do
    it "returns correct counts" do
      present = [0, 1]
      missing = [2, 3, 4]
      recovery_exponents = [0, 1, 2, 3, 4]

      matrix = described_class.new(present, missing, recovery_exponents, 5,
                                   block_size)

      expect(matrix.recovery_count).to eq(5)
      expect(matrix.output_count).to eq(3)
    end
  end

  describe "edge cases" do
    it "handles single missing block" do
      present = [0, 1, 2]
      missing = [3]
      recovery_exponents = [0, 1]

      matrix = described_class.new(present, missing, recovery_exponents, 4,
                                   block_size)
      matrix.compute!

      # Should have 1x1 matrix
      expect(matrix.matrix.size).to eq(1)
      expect(matrix.matrix[0].size).to eq(1)
    end

    it "handles all blocks missing" do
      present = []
      missing = [0, 1, 2]
      recovery_exponents = [0, 1, 2]

      matrix = described_class.new(present, missing, recovery_exponents, 3,
                                   block_size)
      matrix.compute!

      # Should have 3x3 matrix
      expect(matrix.matrix.size).to eq(3)
      expect(matrix.matrix[0].size).to eq(3)
    end

    it "handles maximum missing blocks" do
      # Large but reasonable number
      present = [0]
      missing = (1..10).to_a
      recovery_exponents = (0..15).to_a

      matrix = described_class.new(present, missing, recovery_exponents, 11,
                                   block_size)
      matrix.compute!

      expect(matrix.matrix.size).to eq(10)
      expect(matrix.used_recovery_exponents.size).to eq(10)
    end
  end

  describe "mathematical correctness" do
    it "solves linear system correctly for 2x2 case" do
      # Setup: blocks 0,1 present, block 2,3 missing
      # Use recovery exponents 0,1
      present = [0, 1]
      missing = [2, 3]
      recovery_exponents = [0, 1]

      matrix = described_class.new(present, missing, recovery_exponents, 4,
                                   block_size)
      matrix.compute!

      bases = matrix.bases

      # A matrix should be:
      # [ base[2]^0  base[3]^0 ]   [ 1           1         ]
      # [ base[2]^1  base[3]^1 ] = [ base[2]     base[3]   ]

      # Matrix determinant = base[3] - base[2] (in GF)
      # Which equals base[3] XOR base[2]
      det = Omnizip::Parity::Galois16.add(bases[3], bases[2])

      # Should be non-zero (matrix invertible)
      expect(det).not_to eq(0)

      # Verify matrix inverse exists and works
      a_inv = matrix.matrix.transpose

      # A * A^-1 should be identity
      a = [
        [1, 1],
        [bases[2], bases[3]],
      ]

      product = multiply_matrices(a, a_inv)

      expect(product[0][0]).to eq(1)
      expect(product[0][1]).to eq(0)
      expect(product[1][0]).to eq(0)
      expect(product[1][1]).to eq(1)
    end

    it "produces consistent coefficients across calls" do
      present = [0, 1]
      missing = [2, 3]
      recovery_exponents = [0, 1]

      matrix1 = described_class.new(present, missing, recovery_exponents, 4,
                                    block_size)
      matrix1.compute!

      matrix2 = described_class.new(present, missing, recovery_exponents, 4,
                                    block_size)
      matrix2.compute!

      # Should produce identical matrices
      expect(matrix1.matrix).to eq(matrix2.matrix)
      expect(matrix1.bases).to eq(matrix2.bases)
    end
  end

  # Helper method for matrix multiplication in GF(2^16)
  def multiply_matrices(a, b)
    rows = a.size
    cols = b[0].size
    inner = b.size

    result = Array.new(rows) { Array.new(cols, 0) }

    rows.times do |i|
      cols.times do |j|
        sum = 0
        inner.times do |k|
          product = Omnizip::Parity::Galois16.multiply(a[i][k], b[k][j])
          sum = Omnizip::Parity::Galois16.add(sum, product)
        end
        result[i][j] = sum
      end
    end

    result
  end
end

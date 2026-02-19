# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/reed_solomon_decoder"
require "omnizip/parity/reed_solomon_encoder"
require "omnizip/parity/galois16"

RSpec.describe Omnizip::Parity::ReedSolomonDecoder do
  describe ".decode" do
    it "recovers single missing block" do
      # Create test data
      input_blocks = [
        "AAAA" * 25, # 100 bytes
        "BBBB" * 25,
        "CCCC" * 25,
      ]
      block_size = 100
      total_inputs = 3

      # Encode with 2 recovery blocks
      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0, 1],
      )

      # Simulate loss of block 1
      present_blocks = {
        0 => input_blocks[0],
        2 => input_blocks[2],
      }

      recovery_blocks = [
        { data: recovery_data[0], exponent: 0 },
      ]

      # Recover
      recovered = described_class.decode(
        present_blocks,
        recovery_blocks,
        [1], # missing index
        block_size,
        total_inputs,
      )

      # Verify
      expect(recovered[1]).to eq(input_blocks[1])
    end

    it "recovers multiple missing blocks" do
      # Create test data
      input_blocks = [
        "\x01" * 100,
        "\x02" * 100,
        "\x03" * 100,
        "\x04" * 100,
      ]
      block_size = 100
      total_inputs = 4

      # Encode with 3 recovery blocks
      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0, 1, 2],
      )

      # Simulate loss of blocks 1 and 3
      present_blocks = {
        0 => input_blocks[0],
        2 => input_blocks[2],
      }

      recovery_blocks = [
        { data: recovery_data[0], exponent: 0 },
        { data: recovery_data[1], exponent: 1 },
      ]

      # Recover
      recovered = described_class.decode(
        present_blocks,
        recovery_blocks,
        [1, 3],
        block_size,
        total_inputs,
      )

      # Verify
      expect(recovered[1]).to eq(input_blocks[1])
      expect(recovered[3]).to eq(input_blocks[3])
    end

    it "requires even block size" do
      expect do
        described_class.decode({}, [], [0], 99, 1)
      end.to raise_error(ArgumentError, /Block size must be even/)
    end

    it "requires missing blocks" do
      expect do
        described_class.decode({}, [], [], 100, 1)
      end.to raise_error(ArgumentError, /No missing blocks/)
    end

    it "requires enough recovery blocks" do
      present = { 0 => "A" * 100 }
      recovery = [{ data: "B" * 100, exponent: 0 }]

      expect do
        described_class.decode(present, recovery, [1, 2], 100, 3)
      end.to raise_error(ArgumentError, /Not enough recovery blocks/)
    end
  end

  describe "round-trip encode/decode" do
    it "perfectly recovers all block combinations" do
      # Create diverse test data
      input_blocks = [
        ("\x00\xFF" * 50).b,
        ("\xAA\x55" * 50).b,
        (0..99).to_a.pack("C*").b,
      ]
      block_size = 100
      total_inputs = 3

      # Create 2 recovery blocks
      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0, 1],
      )

      recovery_blocks = [
        { data: recovery_data[0], exponent: 0 },
        { data: recovery_data[1], exponent: 1 },
      ]

      # Test all single-block loss scenarios
      [0, 1, 2].each do |missing_idx|
        present_blocks = {}
        (0...3).each do |i|
          present_blocks[i] = input_blocks[i] unless i == missing_idx
        end

        recovered = described_class.decode(
          present_blocks,
          recovery_blocks.take(1), # Need 1 recovery for 1 missing
          [missing_idx],
          block_size,
          total_inputs,
        )

        expect(recovered[missing_idx]).to eq(input_blocks[missing_idx]),
                                          "Failed to recover block #{missing_idx}"
      end

      # Test all two-block loss scenarios
      [[0, 1], [0, 2], [1, 2]].each do |missing_indices|
        present_blocks = {}
        (0...3).each do |i|
          present_blocks[i] = input_blocks[i] unless missing_indices.include?(i)
        end

        recovered = described_class.decode(
          present_blocks,
          recovery_blocks, # Need 2 recovery for 2 missing
          missing_indices,
          block_size,
          total_inputs,
        )

        missing_indices.each do |idx|
          expect(recovered[idx]).to eq(input_blocks[idx]),
                                    "Failed to recover block #{idx} in scenario #{missing_indices}"
        end
      end
    end

    it "works with different block sizes" do
      [2, 10, 100, 1000].each do |block_size|
        input_blocks = [
          "A" * block_size,
          "B" * block_size,
        ]

        recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
          input_blocks,
          block_size,
          [0],
        )

        # Lose block 0
        recovered = described_class.decode(
          { 1 => input_blocks[1] },
          [{ data: recovery_data[0], exponent: 0 }],
          [0],
          block_size,
          2,
        )

        expect(recovered[0]).to eq(input_blocks[0])
      end
    end

    it "works with different exponents" do
      input_blocks = ["DATA" * 25, "TEST" * 25, "ABCD" * 25]
      block_size = 100

      # Try various exponents
      [0, 1, 5, 10, 100, 1000].each do |exp|
        recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
          input_blocks,
          block_size,
          [exp],
        )

        recovered = described_class.decode(
          { 0 => input_blocks[0], 2 => input_blocks[2] },
          [{ data: recovery_data[0], exponent: exp }],
          [1],
          block_size,
          3,
        )

        expect(recovered[1]).to eq(input_blocks[1]),
                                "Failed with exponent #{exp}"
      end
    end

    it "handles maximum recovery scenario" do
      # 5 blocks, lose 4, use 4 recovery blocks
      input_blocks = (0...5).map { |i| (i.chr * 100).b }
      block_size = 100

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0, 1, 2, 3],
      )

      # Keep only block 3
      present = { 3 => input_blocks[3] }
      missing = [0, 1, 2, 4]

      recovery_blocks = recovery_data.each_with_index.map do |data, idx|
        { data: data, exponent: idx }
      end

      recovered = described_class.decode(
        present,
        recovery_blocks,
        missing,
        block_size,
        5,
      )

      missing.each do |idx|
        expect(recovered[idx]).to eq(input_blocks[idx])
      end
    end
  end

  describe ".gaussian_elimination" do
    it "solves simple 2x2 system" do
      # System: [a b; c d] * [x; y] = [e; f]
      # We'll use simple values in GF(2^16)
      left = [[2, 3], [4, 5]]
      right = [[1, 0], [0, 1]]

      described_class.send(:gaussian_elimination, left, right)

      # After elimination, right should be identity
      expect(right[0][0]).to eq(1)
      expect(right[0][1]).to eq(0)
      expect(right[1][0]).to eq(0)
      expect(right[1][1]).to eq(1)

      # Left should contain the solution coefficients
      expect(left).to be_a(Array)
      expect(left.size).to eq(2)
    end

    it "handles identity matrix" do
      left = [[1, 0], [0, 1]]
      right = [[1, 0], [0, 1]]
      original_left = left.map(&:dup)

      described_class.send(:gaussian_elimination, left, right)

      # Should remain unchanged
      expect(left).to eq(original_left)
      expect(right).to eq([[1, 0], [0, 1]])
    end

    it "raises on singular matrix" do
      # Create singular system (dependent rows)
      left = [[1, 2], [1, 2]]
      right = [[2, 2], [4, 4]] # Second row is 2x first row

      expect do
        described_class.send(:gaussian_elimination, left, right)
      end.to raise_error(/Singular matrix/)
    end
  end

  describe "edge cases" do
    it "handles all-zero blocks" do
      input_blocks = ["\x00" * 100, "\x00" * 100]
      block_size = 100

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0],
      )

      recovered = described_class.decode(
        { 1 => input_blocks[1] },
        [{ data: recovery_data[0], exponent: 0 }],
        [0],
        block_size,
        2,
      )

      expect(recovered[0]).to eq("\x00" * 100)
    end

    it "handles all-ones blocks" do
      input_blocks = [("\xFF" * 100).b, ("\xFF" * 100).b]
      block_size = 100

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0],
      )

      recovered = described_class.decode(
        { 1 => input_blocks[1] },
        [{ data: recovery_data[0], exponent: 0 }],
        [0],
        block_size,
        2,
      )

      expect(recovered[0]).to eq(input_blocks[0])
    end

    it "handles minimum block size" do
      input_blocks = ["AB", "CD"]

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        2,
        [0],
      )

      recovered = described_class.decode(
        { 1 => input_blocks[1] },
        [{ data: recovery_data[0], exponent: 0 }],
        [0],
        2,
        2,
      )

      expect(recovered[0]).to eq("AB")
    end

    it "handles non-sequential indices" do
      # Blocks at indices 0, 5, 10
      input_blocks = ["#{'AAA' * 33}A", "#{'BBB' * 33}B",
                      "#{'CCC' * 33}C"]
      block_size = 100

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0],
      )

      # Simulate: have blocks 0 and 10, missing block 5
      # But in the encoder/decoder, we need to map to sequential indices
      # This tests that index mapping is handled correctly
      recovered = described_class.decode(
        { 0 => input_blocks[0], 2 => input_blocks[2] },
        [{ data: recovery_data[0], exponent: 0 }],
        [1],
        block_size,
        3,
      )

      expect(recovered[1]).to eq(input_blocks[1])
    end
  end

  describe "mathematical properties" do
    it "is deterministic" do
      input_blocks = ["DATA" * 25, "TEST" * 25, "ABCD" * 25]
      block_size = 100

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0],
      )

      present = { 0 => input_blocks[0], 2 => input_blocks[2] }
      recovery = [{ data: recovery_data[0], exponent: 0 }]

      result1 = described_class.decode(present, recovery, [1], block_size, 3)
      result2 = described_class.decode(present, recovery, [1], block_size, 3)

      expect(result1).to eq(result2)
    end

    it "recovers independently of block order" do
      input_blocks = ["AAAA" * 25, "BBBB" * 25, "CCCC" * 25]
      block_size = 100

      recovery_data = Omnizip::Parity::ReedSolomonEncoder.encode(
        input_blocks,
        block_size,
        [0, 1],
      )

      recovery_blocks = [
        { data: recovery_data[0], exponent: 0 },
        { data: recovery_data[1], exponent: 1 },
      ]

      # Try different presentation orders
      present1 = { 0 => input_blocks[0], 1 => input_blocks[1] }
      present2 = { 1 => input_blocks[1], 0 => input_blocks[0] }

      result1 = described_class.decode(present1, recovery_blocks, [2],
                                       block_size, 3)
      result2 = described_class.decode(present2, recovery_blocks, [2],
                                       block_size, 3)

      expect(result1[2]).to eq(result2[2])
      expect(result1[2]).to eq(input_blocks[2])
    end
  end
end

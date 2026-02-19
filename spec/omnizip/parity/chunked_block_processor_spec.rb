# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/chunked_block_processor"
require "omnizip/parity/reed_solomon_matrix"
require "omnizip/parity/reed_solomon_encoder"
require "omnizip/parity/galois16"

RSpec.describe Omnizip::Parity::ChunkedBlockProcessor do
  let(:block_size) { 100 }

  describe "#initialize" do
    it "stores all parameters" do
      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => "A" * block_size }
      recovery = { 0 => "B" * block_size }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)

      expect(processor.matrix).to eq(matrix)
      expect(processor.present_blocks).to eq(present)
      expect(processor.recovery_blocks).to eq(recovery)
      expect(processor.missing_indices).to eq([1])
      expect(processor.block_size).to eq(block_size)
    end

    it "sorts missing indices" do
      matrix = create_test_matrix([0], [2, 1], [0, 1], 3, block_size)
      present = { 0 => "A" * block_size }
      recovery = { 0 => "B" * block_size, 1 => "C" * block_size }
      missing = [2, 1] # Unsorted

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)

      expect(processor.missing_indices).to eq([1, 2])
    end

    it "caps chunk size at block size" do
      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => "A" * block_size }
      recovery = { 0 => "B" * block_size }
      missing = [1]

      # Request huge chunk size
      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: 10_000)

      # Should be capped at block_size
      expect(processor.chunk_size).to eq(block_size)
    end

    it "uses default chunk size when not specified" do
      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => "A" * block_size }
      recovery = { 0 => "B" * block_size }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)

      # Should use DEFAULT_CHUNK_SIZE or block_size, whichever is smaller
      expected = [described_class::DEFAULT_CHUNK_SIZE, block_size].min
      expect(processor.chunk_size).to eq(expected)
    end
  end

  describe "#process_all" do
    it "recovers missing block correctly (single missing, exponent 0)" do
      # Simple case: 2 inputs, 1 missing, using exponent 0 (XOR)
      input0_data = "\x01\x00" * 50
      input1_data = "\x02\x00" * 50

      # Create recovery: recovery[0] = input0 XOR input1 (for exponent 0)
      recovery_data = create_recovery_blocks([input0_data, input1_data],
                                             block_size, [0])[0]

      # Setup: input0 present, input1 missing
      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_data }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: block_size)
      recovered = processor.process_all

      # Should recover input1 exactly
      expect(recovered[1]).to eq(input1_data)
    end

    it "handles chunked processing (multiple chunks)" do
      # Use small chunk size to force multiple iterations
      chunk_size = 10

      input0_data = "\x11\x00" * 50
      input1_data = "\x22\x00" * 50

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: chunk_size)
      recovered = processor.process_all

      # Should recover correctly even with chunked processing
      expect(recovered[1]).to eq(input1_data)
    end

    it "initializes output blocks with zeros" do
      input0_data = "A" * block_size
      recovery_data = "B" * block_size

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_data }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)
      recovered = processor.process_all

      # Output should exist and have correct size
      expect(recovered).to have_key(1)
      expect(recovered[1].size).to eq(block_size)
    end

    it "processes all chunks up to block_size" do
      # Verify that all offsets are processed
      chunk_size = 30 # Will need 4 chunks for 100 bytes

      input0_data = (0..49).map { |i| [i % 256, 0].pack("C*") }.join
      input1_data = (50..99).map { |i| [i % 256, 0].pack("C*") }.join

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: chunk_size)
      recovered = processor.process_all

      # Entire block should be recovered
      expect(recovered[1]).to eq(input1_data)
    end

    it "creates output blocks for all missing indices" do
      input0_data = "\x01\x00" * 50
      input1_data = "\x02\x00" * 50
      input2_data = "\x03\x00" * 50

      recovery_blocks = create_recovery_blocks(
        [input0_data, input1_data, input2_data], block_size, [0, 1]
      )

      matrix = create_test_matrix([0], [1, 2], [0, 1], 3, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0], 1 => recovery_blocks[1] }
      missing = [1, 2]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)
      recovered = processor.process_all

      # Should create blocks for both missing indices
      expect(recovered).to have_key(1)
      expect(recovered).to have_key(2)
      expect(recovered[1].size).to eq(block_size)
      expect(recovered[2].size).to eq(block_size)
    end
  end

  describe "b-vector computation" do
    it "starts with recovery block data" do
      # With no present blocks, b-vector should equal recovery block
      input0_data = "\x10\x00" * 50

      recovery_blocks = create_recovery_blocks([input0_data], block_size, [5])

      matrix = create_test_matrix([], [0], [5], 1, block_size)
      present = {}
      recovery = { 5 => recovery_blocks[0] }
      missing = [0]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)
      recovered = processor.process_all

      # Should match input (with exponent 5, single block)
      expect(recovered[0]).to eq(input0_data)
    end

    it "processes recovery blocks in order" do
      input0_data = "\x03\x00" * 50

      recovery_blocks = create_recovery_blocks([input0_data], block_size, [0])

      matrix = create_test_matrix([], [0], [0], 1, block_size)
      present = {}
      recovery = { 0 => recovery_blocks[0] }
      missing = [0]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)
      recovered = processor.process_all

      # Should recover correctly
      expect(recovered[0]).to eq(input0_data)
    end
  end

  describe "edge cases" do
    it "handles all-zero input" do
      input0_data = "\x00" * block_size
      input1_data = "\x00" * block_size

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)
      recovered = processor.process_all

      expect(recovered[1]).to eq("\x00" * block_size)
    end

    it "handles minimum block size (2 bytes)" do
      tiny_block_size = 2
      input0_data = "\x01\x00"
      input1_data = "\x02\x00"

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               tiny_block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, tiny_block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      tiny_block_size, chunk_size: 2)
      recovered = processor.process_all

      expect(recovered[1]).to eq(input1_data)
    end

    it "handles exact chunk size match" do
      # When chunk_size equals block_size, process in one chunk
      input0_data = "\x33\x00" * 50
      input1_data = "\x66\x00" * 50

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: block_size)
      recovered = processor.process_all

      expect(recovered[1]).to eq(input1_data)
    end

    it "handles partial last chunk" do
      # chunk_size doesn't divide evenly into block_size
      chunk_size = 35 # 100 / 35 = 2 chunks + 30 byte remainder

      input0_data = (0..49).map { |i| [i, 0].pack("C*") }.join
      input1_data = (50..99).map { |i| [i, 0].pack("C*") }.join

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: chunk_size)
      recovered = processor.process_all

      expect(recovered[1]).to eq(input1_data)
    end

    it "handles very small chunks (2 bytes)" do
      # Extreme chunking: 1 word at a time
      input0_data = ("\x42\x00" * 50).b
      input1_data = ("\x84\x00" * 50).b

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size, chunk_size: 2)
      recovered = processor.process_all

      expect(recovered[1]).to eq(input1_data)
    end
  end

  describe "mathematical correctness" do
    it "recovers blocks using different exponents" do
      # Test with non-zero exponents
      input0_data = "\x07\x00" * 50
      input1_data = "\x0D\x00" * 50

      # Use exponent 3 instead of 0
      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [3])

      matrix = create_test_matrix([0], [1], [3], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 3 => recovery_blocks[0] }
      missing = [1]

      processor = described_class.new(matrix, present, recovery, missing,
                                      block_size)
      recovered = processor.process_all

      expect(recovered[1]).to eq(input1_data)
    end

    it "produces consistent results with different chunk sizes" do
      input0_data = "\x11\x00" * 50
      input1_data = "\x22\x00" * 50

      recovery_blocks = create_recovery_blocks([input0_data, input1_data],
                                               block_size, [0])

      matrix = create_test_matrix([0], [1], [0], 2, block_size)
      present = { 0 => input0_data }
      recovery = { 0 => recovery_blocks[0] }
      missing = [1]

      # Process with different chunk sizes
      processor1 = described_class.new(matrix, present, recovery, missing,
                                       block_size, chunk_size: block_size)
      recovered1 = processor1.process_all

      processor2 = described_class.new(matrix, present, recovery, missing,
                                       block_size, chunk_size: 10)
      recovered2 = processor2.process_all

      # Should give same result
      expect(recovered1[1]).to eq(recovered2[1])
    end
  end

  # Helper methods

  # Create a ReedSolomonMatrix for testing
  def create_test_matrix(present_indices, missing_indices, recovery_exponents,
total_inputs, block_size)
    matrix = Omnizip::Parity::ReedSolomonMatrix.new(
      present_indices,
      missing_indices,
      recovery_exponents,
      total_inputs,
      block_size,
    )
    matrix.compute!
    matrix
  end

  # Create recovery blocks using ReedSolomonEncoder
  def create_recovery_blocks(input_blocks, block_size, exponents)
    Omnizip::Parity::ReedSolomonEncoder.encode(input_blocks, block_size,
                                               exponents)
  end
end

# frozen_string_literal: true

require "spec_helper"
require "omnizip/parity/reed_solomon_encoder"
require "omnizip/parity/galois16"

RSpec.describe Omnizip::Parity::ReedSolomonEncoder do
  describe ".encode" do
    it "creates recovery blocks" do
      # Simple test data
      input_blocks = [
        "AB".b * 50, # 100 bytes
        "CD".b * 50,
        "EF".b * 50,
      ]
      block_size = 100
      exponents = [0, 1]

      recovery_blocks = described_class.encode(input_blocks, block_size,
                                               exponents)

      expect(recovery_blocks.size).to eq(2)
      recovery_blocks.each do |block|
        expect(block.bytesize).to eq(block_size)
      end
    end

    it "requires even block size" do
      input_blocks = ["A" * 99]
      expect do
        described_class.encode(input_blocks, 99, [0])
      end.to raise_error(ArgumentError, /Block size must be even/)
    end

    it "requires input blocks" do
      expect do
        described_class.encode([], 100, [0])
      end.to raise_error(ArgumentError, /No input blocks/)
    end

    it "requires exponents" do
      input_blocks = ["AB" * 50]
      expect do
        described_class.encode(input_blocks, 100, [])
      end.to raise_error(ArgumentError, /No exponents/)
    end

    it "validates input block sizes" do
      input_blocks = ["A" * 100, "B" * 98]
      expect do
        described_class.encode(input_blocks, 100, [0])
      end.to raise_error(ArgumentError, /Input block 1 has size 98/)
    end

    it "handles zero exponent (simple XOR)" do
      # With exponent 0, base^0 = 1, so recovery = XOR of all inputs
      input1 = "\x01\x00".b * 50
      input2 = "\x02\x00".b * 50
      input3 = "\x03\x00".b * 50
      input_blocks = [input1, input2, input3]

      recovery = described_class.encode(input_blocks, 100, [0])

      # Expected: 0x01 ^ 0x02 ^ 0x03 = 0x00
      expect(recovery[0]).to eq("\x00".b * 100)
    end

    it "produces different recovery blocks for different exponents" do
      # Use TWO input blocks so recovery blocks will differ
      input_blocks = ["DATA".b * 25, "TEST".b * 25]
      block_size = 100

      recovery0 = described_class.encode(input_blocks, block_size, [0])
      recovery1 = described_class.encode(input_blocks, block_size, [1])
      recovery2 = described_class.encode(input_blocks, block_size, [2])

      expect(recovery0[0]).not_to eq(recovery1[0])
      expect(recovery1[0]).not_to eq(recovery2[0])
      expect(recovery0[0]).not_to eq(recovery2[0])
    end

    it "produces deterministic output" do
      input_blocks = [("test" * 25).b]
      block_size = 100
      exponents = [5, 10]

      result1 = described_class.encode(input_blocks, block_size, exponents)
      result2 = described_class.encode(input_blocks, block_size, exponents)

      expect(result1).to eq(result2)
    end
  end

  describe ".process_block" do
    it "performs output ^= input * factor correctly" do
      factor = 7
      input = "\x05\x00\x0A\x00".b # [5, 10] as 16-bit words
      output = "\x00\x00\x00\x00".b.dup

      described_class.send(:process_block, factor, input, output, 4)

      # Expected: output = 0 ^ (5*7, 10*7) = (35, 70)
      expected_word1 = Omnizip::Parity::Galois16.multiply(5, 7)
      expected_word2 = Omnizip::Parity::Galois16.multiply(10, 7)

      result_word1 = output.getbyte(0) | (output.getbyte(1) << 8)
      result_word2 = output.getbyte(2) | (output.getbyte(3) << 8)

      expect(result_word1).to eq(expected_word1)
      expect(result_word2).to eq(expected_word2)
    end

    it "accumulates multiple operations (XOR)" do
      factor = 3
      input = "\x02\x00".b
      output = "\x01\x00".b.dup

      # First operation: output = 1 ^ (2 * 3)
      described_class.send(:process_block, factor, input, output, 2)
      first_result = output.getbyte(0) | (output.getbyte(1) << 8)

      expected = Omnizip::Parity::Galois16.add(
        1,
        Omnizip::Parity::Galois16.multiply(2, 3),
      )
      expect(first_result).to eq(expected)

      # Second operation: output ^= (2 * 3) again
      described_class.send(:process_block, factor, input, output, 2)
      second_result = output.getbyte(0) | (output.getbyte(1) << 8)

      # Should return to 1 (XOR twice cancels)
      expect(second_result).to eq(1)
    end

    it "handles little-endian 16-bit words" do
      factor = 2
      # 0x0201 as bytes = 0x0102 as 16-bit LE word = 258
      input = "\x01\x02".b
      output = "\x00\x00".b.dup

      described_class.send(:process_block, factor, input, output, 2)

      word = output.getbyte(0) | (output.getbyte(1) << 8)
      expected = Omnizip::Parity::Galois16.multiply(0x0201, 2)

      expect(word).to eq(expected)
    end
  end

  describe "par2cmdline compatibility" do
    # These tests verify that our encoder produces identical output to par2cmdline

    it "matches par2cmdline for simple data" do
      # Create simple repeating pattern like par2cmdline test data
      input_blocks = [
        (0..255).to_a.pack("C*").b, # 256 bytes of 0-255
        255.downto(0).to_a.pack("C*").b, # 256 bytes of 255-0
      ]
      block_size = 256
      exponent = 0 # First recovery block

      recovery = described_class.encode(input_blocks, block_size, [exponent])

      # With exponentponent 0, all bases are 1, so recovery = XOR of inputs
      # This should produce alternating 0xFF and 0x00
      expected = input_blocks[0].bytes.zip(input_blocks[1].bytes).map do |a, b|
        a ^ b
      end.pack("C*")

      expect(recovery[0]).to eq(expected)
    end

    context "par2cmdline compatibility" do
      it "uses same base selection as par2cmdline" do
        # Par2cmdline uses sequential logbases: base[i] = antilog[i]
        # This means logbase values are 0, 1, 2, 3, 4, 5, ...
        # base[0] = antilog[0] = 1
        # base[1] = antilog[1] = 2 (generator)
        # base[2] = antilog[2] = 4
        # etc.
        bases = Omnizip::Parity::Galois16.select_bases(10)

        # Verify we get sequential powers of the generator starting from 1
        expect(bases[0]).to eq(1)   # 2^0
        expect(bases[1]).to eq(2)   # 2^1
        expect(bases[2]).to eq(4)   # 2^2
        expect(bases[3]).to eq(8)   # 2^3
        expect(bases[4]).to eq(16)  # 2^4
        expect(bases[5]).to eq(32)  # 2^5

        # Verify bases are in sequence (not skipping non-coprime values)
        expect(bases.size).to eq(10)
      end
    end

    it "produces correct recovery for known par2 test case" do
      # Use our simple 2-file fixture
      par2_file = File.join(__dir__,
                            "../../fixtures/par2cmdline/flatdata-par2files/testdata.par2")

      # Parse PAR2 to get recovery blocks
      require_relative "../../../lib/omnizip/parity/par2_verifier"
      verifier = Omnizip::Parity::Par2Verifier.new(par2_file)
      verifier.verify

      # Get file data
      dir = File.dirname(par2_file)
      file_list = verifier.instance_variable_get(:@file_list)
      block_size = verifier.instance_variable_get(:@metadata)[:block_size]

      # Read all input blocks
      input_blocks = []
      file_list.each do |file_info|
        file_path = File.join(dir, file_info[:filename])
        File.open(file_path, "rb") do |io|
          while (data = io.read(block_size))
            data += "\x00" * (block_size - data.bytesize) if data.bytesize < block_size
            input_blocks << data
          end
        end
      end

      # Get recovery blocks from PAR2
      recovery_blocks = verifier.instance_variable_get(:@recovery_blocks)

      # Compare first recovery block (exponent 0) with our encoding
      our_recovery = described_class.encode(input_blocks, block_size, [0])
      par2_recovery_0 = recovery_blocks.find { |r| r[:exponent] == 0 }

      expect(our_recovery[0]).to eq(par2_recovery_0[:data])
    end
  end

  describe "mathematical properties" do
    it "satisfies linearity: encode(a+b) = encode(a) + encode(b)" do
      # In GF(2^16), addition is XOR
      block_size = 100

      input_a = ["\x11" * block_size]
      input_b = ["\x22" * block_size]
      input_sum = [(0x11 ^ 0x22).chr * block_size]

      recovery_a = described_class.encode(input_a, block_size, [5])[0]
      recovery_b = described_class.encode(input_b, block_size, [5])[0]
      recovery_sum = described_class.encode(input_sum, block_size, [5])[0]

      # recovery(a) XOR recovery(b) should equal recovery(a XOR b)
      computed_sum = recovery_a.bytes.zip(recovery_b.bytes).map do |a, b|
        a ^ b
      end.pack("C*")

      expect(computed_sum).to eq(recovery_sum)
    end

    it "satisfies scalar multiplication: encode(c*a) = c*encode(a)" do
      block_size = 4
      scalar = 7

      # Create input: all words are value 5
      input = ["\x05\x00" * 2]

      # Compute encode(input)
      recovery = described_class.encode(input, block_size, [3])[0]

      # Now compute c * input
      scaled_input_word = Omnizip::Parity::Galois16.multiply(5, scalar)
      scaled_input_data = [scaled_input_word].pack("v").b * 2

      # Compute encode(c * input)
      scaled_recovery = described_class.encode([scaled_input_data], block_size,
                                               [3])[0]

      # Now compute c * recovery
      manual_scaled = recovery.dup
      (block_size / 2).times do |i|
        offset = i * 2
        word = recovery.getbyte(offset) | (recovery.getbyte(offset + 1) << 8)
        scaled_word = Omnizip::Parity::Galois16.multiply(word, scalar)
        manual_scaled.setbyte(offset, scaled_word & 0xFF)
        manual_scaled.setbyte(offset + 1, (scaled_word >> 8) & 0xFF)
      end

      expect(scaled_recovery).to eq(manual_scaled)
    end
  end

  describe "edge cases" do
    it "handles all-zero input" do
      input_blocks = ["\x00" * 100]
      recovery = described_class.encode(input_blocks, 100, [0, 1, 2])

      # All zeros should produce all zeros
      recovery.each do |block|
        expect(block).to eq("\x00" * 100)
      end
    end

    it "handles all-ones input" do
      input_blocks = ["\xFF" * 100]
      recovery = described_class.encode(input_blocks, 100, [0])

      # Should produce some non-zero output
      expect(recovery[0]).not_to eq("\x00" * 100)
    end

    it "handles maximum exponent" do
      input_blocks = ["AB" * 50]
      # Large but valid exponent
      recovery = described_class.encode(input_blocks, 100, [65535])

      expect(recovery[0].bytesize).to eq(100)
    end

    it "handles many exponents" do
      # Use multiple input blocks so recovery blocks will differ
      input_blocks = ["DATA" * 25, "TEST" * 25, "ABCD" * 25]
      exponents = (0..99).to_a

      recovery = described_class.encode(input_blocks, 100, exponents)

      expect(recovery.size).to eq(100)
      # All should be different (with multiple input blocks)
      expect(recovery.uniq.size).to eq(100)
    end

    it "handles minimum block size" do
      # Minimum is 2 bytes (one 16-bit word)
      input_blocks = ["AB"]
      recovery = described_class.encode(input_blocks, 2, [0])

      expect(recovery[0].bytesize).to eq(2)
    end
  end
end

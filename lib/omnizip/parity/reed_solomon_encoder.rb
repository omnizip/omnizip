# frozen_string_literal: true

require_relative "galois16"
require_relative "par2cmdline_algorithm"

module Omnizip
  module Parity
    # Pure Reed-Solomon encoder for creating recovery blocks
    # This is algorithm-only code with no I/O dependencies
    #
    # Creates recovery blocks using Vandermonde matrix over GF(2^16):
    #   Recovery[i] = sum(Input[j] * Base[j]^Exponent[i] for all j)
    class ReedSolomonEncoder
      # Create recovery blocks from input blocks
      #
      # @param input_blocks [Array<String>] Array of input block data (binary strings)
      # @param block_size [Integer] Size of each block in bytes (must be even for 16-bit processing)
      # @param exponents [Array<Integer>] Exponent for each recovery block (0-65535)
      # @return [Array<String>] Array of recovery block data (binary strings)
      def self.encode(input_blocks, block_size, exponents)
        if block_size.odd?
          raise ArgumentError,
                "Block size must be even for 16-bit processing"
        end
        raise ArgumentError, "No input blocks provided" if input_blocks.empty?
        raise ArgumentError, "No exponents provided" if exponents.empty?

        # Validate all input blocks have correct size
        input_blocks.each_with_index do |block, idx|
          unless block.bytesize == block_size
            raise ArgumentError,
                  "Input block #{idx} has size #{block.bytesize}, expected #{block_size}"
          end
        end

        # Select base values using par2cmdline algorithm
        num_inputs = input_blocks.length
        bases = Par2cmdlineAlgorithm.compute_bases(num_inputs)

        # Create recovery blocks
        recovery_blocks = []
        exponents.each do |exponent|
          recovery_block = create_recovery_block(input_blocks, bases, exponent,
                                                 block_size)
          recovery_blocks << recovery_block
        end

        recovery_blocks
      end

      # Create a single recovery block
      #
      # @param input_blocks [Array<String>] Input block data
      # @param bases [Array<Integer>] Base values for each input
      # @param exponent [Integer] Exponent for this recovery block
      # @param block_size [Integer] Block size in bytes
      # @return [String] Recovery block data
      def self.create_recovery_block(input_blocks, bases, exponent, block_size)
        # Initialize recovery block to zeros
        recovery_data = "\x00".b * block_size

        # Process each input block
        input_blocks.each_with_index do |input_block, idx|
          # Compute factor = base[idx]^exponent
          factor = Galois16.power(bases[idx], exponent)

          # Skip if factor is zero (optimization)
          next if factor.zero?

          # Add input_block * factor to recovery_block
          process_block(factor, input_block, recovery_data, block_size)
        end

        recovery_data
      end

      # Core operation: output_block ^= input_block * factor (in GF(2^16))
      # Processes data as 16-bit words in little-endian format
      #
      # @param factor [Integer] Galois field multiplier
      # @param input_block [String] Input data
      # @param output_block [String] Output data (modified in place)
      # @param block_size [Integer] Block size in bytes
      def self.process_block(factor, input_block, output_block, block_size)
        # Process as 16-bit words (little-endian)
        num_words = block_size / 2

        num_words.times do |i|
          offset = i * 2

          # Read 16-bit words (little-endian)
          input_word = input_block.getbyte(offset) |
            (input_block.getbyte(offset + 1) << 8)

          output_word = output_block.getbyte(offset) |
            (output_block.getbyte(offset + 1) << 8)

          # Galois multiplication and addition (XOR)
          result = Galois16.add(output_word,
                                Galois16.multiply(input_word, factor))

          # Write back as bytes (little-endian)
          output_block.setbyte(offset, result & 0xFF)
          output_block.setbyte(offset + 1, (result >> 8) & 0xFF)
        end
      end

      private_class_method :create_recovery_block, :process_block
    end
  end
end

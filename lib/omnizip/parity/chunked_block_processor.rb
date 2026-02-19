# frozen_string_literal: true

require_relative "reed_solomon_matrix"

module Omnizip
  module Parity
    # Chunked block processor for incremental Reed-Solomon recovery
    #
    # Implements correct RS decoding: x = A^-1 * b
    # where b[i] = recovery[i] - sum(present[k] * base[present[k]]^exponent[i])
    #
    # Processes large blocks incrementally in memory-efficient chunks.
    class ChunkedBlockProcessor
      # Default chunk size (1MB)
      DEFAULT_CHUNK_SIZE = 1024 * 1024

      # @return [ReedSolomonMatrix] RS matrix with precomputed coefficients
      attr_reader :matrix

      # @return [Hash<Integer, String>] Present input blocks (index => data)
      attr_reader :present_blocks

      # @return [Hash<Integer, String>] Recovery blocks (exponent => data)
      attr_reader :recovery_blocks

      # @return [Array<Integer>] Missing block indices to recover
      attr_reader :missing_indices

      # @return [Integer] Block size in bytes
      attr_reader :block_size

      # @return [Integer] Chunk size for processing
      attr_reader :chunk_size

      # Initialize processor
      #
      # @param matrix [ReedSolomonMatrix] Precomputed RS matrix (A^-1)
      # @param present_blocks [Hash<Integer, String>] Present data blocks
      # @param recovery_blocks [Hash<Integer, String>] Recovery blocks (by exponent)
      # @param missing_indices [Array<Integer>] Indices to recover
      # @param block_size [Integer] Block size in bytes
      # @param chunk_size [Integer] Chunk size for processing
      def initialize(matrix, present_blocks, recovery_blocks, missing_indices,
 block_size, chunk_size: DEFAULT_CHUNK_SIZE)
        @matrix = matrix
        @present_blocks = present_blocks
        @recovery_blocks = recovery_blocks
        @missing_indices = missing_indices.sort
        @block_size = block_size
        # Ensure chunk_size is even (we process 16-bit words)
        requested_chunk = [chunk_size, block_size].min
        @chunk_size = requested_chunk - (requested_chunk % 2)
      end

      # Process all blocks incrementally
      #
      # Implements: x = A^-1 * b
      # where b = recovery - present_contributions
      #
      # @return [Hash<Integer, String>] Recovered blocks
      def process_all
        # Initialize output blocks (all zeros)
        recovered = {}
        missing_indices.each do |idx|
          recovered[idx] = "\x00".b * block_size
        end

        # Process block chunk by chunk
        block_offset = 0
        while block_offset < block_size
          current_chunk_size = [chunk_size, block_size - block_offset].min
          process_chunk_at_offset(recovered, block_offset, current_chunk_size)
          block_offset += current_chunk_size
        end

        recovered
      end

      private

      # Process one chunk at given offset
      #
      # For each chunk, we:
      # 1. Compute b_vector chunks from recovery blocks
      # 2. Subtract present block contributions to get final b
      # 3. Apply A^-1 matrix to b to get recovered chunks
      #
      # @param recovered [Hash<Integer, String>] Recovered blocks being built
      # @param offset [Integer] Current offset within blocks
      # @param length [Integer] Chunk length
      def process_chunk_at_offset(recovered, offset, length)
        # Step 1: Initialize b vector from recovery blocks
        # b_vector[i] starts as recovery[i] (for each recovery exponent used)
        b_vector = compute_b_vector_chunks(offset, length)

        # Step 2: Apply A^-1 to b vector to get recovered chunks
        # For each missing block j: recovered[j] = sum(A^-1[j,i] * b[i])
        apply_inverse_matrix(recovered, b_vector, offset, length)
      end

      # Compute b vector chunks
      #
      # b[i] = recovery[i] - sum(present[k] * base[present[k]]^exponent[i])
      #
      # @param offset [Integer] Offset within blocks
      # @param length [Integer] Chunk length
      # @return [Array<String>] B vector chunks (one per recovery block used)
      def compute_b_vector_chunks(offset, length)
        b_chunks = []

        # For each recovery block being used (must match matrix computation!)
        matrix.used_recovery_exponents.each_with_index do |exponent, _exp_idx|
          # Start with recovery block chunk
          recovery_data = recovery_blocks[exponent]
          b_chunk = recovery_data[offset, length].dup

          # Subtract contributions from present blocks
          present_blocks.each do |present_idx, present_data|
            coefficient = matrix.present_contribution_coefficient(present_idx,
                                                                  exponent)
            next if coefficient.zero?

            present_chunk = present_data[offset, length]

            # Subtract: b -= present * coefficient
            # In GF(2^16), subtraction is XOR, so: b ^= present * coefficient
            subtract_contribution(b_chunk, present_chunk, coefficient, length)
          end

          b_chunks << b_chunk
        end

        b_chunks
      end

      # Subtract present block contribution from b chunk
      #
      # b_chunk ^= present_chunk * coefficient (GF subtraction is XOR)
      #
      # @param b_chunk [String] B vector chunk (modified in place)
      # @param present_chunk [String] Present block chunk
      # @param coefficient [Integer] Galois field coefficient
      # @param length [Integer] Chunk length
      def subtract_contribution(b_chunk, present_chunk, coefficient, length)
        num_words = length / 2

        num_words.times do |i|
          word_offset = i * 2

          # Read present word
          present_word = present_chunk.getbyte(word_offset) |
            (present_chunk.getbyte(word_offset + 1) << 8)

          # Read current b word
          b_word = b_chunk.getbyte(word_offset) |
            (b_chunk.getbyte(word_offset + 1) << 8)

          # Compute: b ^= present * coefficient
          contribution = Galois16.multiply(present_word, coefficient)
          result = Galois16.add(b_word, contribution) # add is XOR in GF(2^16)

          # Write back
          b_chunk.setbyte(word_offset, result & 0xFF)
          b_chunk.setbyte(word_offset + 1, (result >> 8) & 0xFF)
        end
      end

      # Apply inverse matrix to b vector
      #
      # For each missing block j:
      #   recovered[j] += sum_i(A^-1[j,i] * b[i])
      #
      # @param recovered [Hash<Integer, String>] Recovered blocks being built
      # @param b_vector [Array<String>] B vector chunks
      # @param offset [Integer] Offset within blocks
      # @param length [Integer] Chunk length
      def apply_inverse_matrix(recovered, b_vector, offset, length)
        # For each output (missing block)
        missing_indices.each_with_index do |missing_idx, output_idx|
          output_block = recovered[missing_idx]

          # For each b vector element (recovery block)
          b_vector.each_with_index do |b_chunk, recovery_idx|
            # Get coefficient from A^-1
            coefficient = matrix.coefficient(output_idx, recovery_idx)
            next if coefficient.zero?

            # CRITICAL: Accumulate chunk at the correct offset
            matrix.process_chunk(coefficient, b_chunk, output_block, length,
                                 output_offset: offset)
          end
        end
      end
    end
  end
end

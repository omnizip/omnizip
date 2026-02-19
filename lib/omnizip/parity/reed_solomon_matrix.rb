# frozen_string_literal: true

require_relative "galois16"
require_relative "par2cmdline_algorithm"

module Omnizip
  module Parity
    # Reed-Solomon matrix for incremental chunk processing
    #
    # This class computes the RS matrix coefficients ONCE using Gaussian
    # elimination, then provides methods to apply those coefficients
    # incrementally to data chunks.
    #
    # Based on par2cmdline's approach (reedsolomon.h, par2repairer.cpp)
    class ReedSolomonMatrix
      # @return [Array<Integer>] Indices of present input blocks
      attr_reader :present_indices

      # @return [Array<Integer>] Indices of missing input blocks
      attr_reader :missing_indices

      # @return [Array<Integer>] All available recovery exponents
      attr_reader :recovery_exponents

      # @return [Array<Integer>] Recovery exponents actually used (first num_missing)
      attr_reader :used_recovery_exponents

      # @return [Integer] Total number of input blocks
      attr_reader :total_inputs

      # @return [Integer] Block size in bytes
      attr_reader :block_size

      # @return [Array<Array<Integer>>] Solved matrix coefficients (num_missing x num_missing)
      attr_reader :matrix

      # @return [Array<Integer>] Selected bases for Galois field
      attr_reader :bases

      # Initialize matrix
      #
      # @param present_indices [Array<Integer>] Indices of available data blocks
      # @param missing_indices [Array<Integer>] Indices of blocks to recover
      # @param recovery_exponents [Array<Integer>] Exponents of recovery blocks to use
      # @param total_inputs [Integer] Total number of input blocks (present + missing)
      # @param block_size [Integer] Block size in bytes
      def initialize(present_indices, missing_indices, recovery_exponents,
total_inputs, block_size)
        @present_indices = present_indices.sort
        @missing_indices = missing_indices.sort
        @recovery_exponents = recovery_exponents.sort
        @total_inputs = total_inputs
        @block_size = block_size
        @matrix = nil # Computed by compute!
        @bases = nil  # Computed by compute!
        @used_recovery_exponents = nil # Computed by compute!
      end

      # Compute matrix coefficients using Gaussian elimination
      #
      # CORRECT FORMULATION:
      # We solve: A * x = b
      # where:
      # - A[i,j] = base[missing[j]]^exponent[i]  (num_missing x num_missing)
      # - x[j] = missing_block[j] (what we solve for)
      # - b[i] = recovery[i] - sum(present[k] * base[present[k]]^exponent[i])
      #
      # This method computes A^-1, so we can later compute:
      # x = A^-1 * b
      #
      # @return [void]
      def compute!
        @bases = Par2cmdlineAlgorithm.compute_bases(total_inputs)

        num_missing = missing_indices.size

        # Select which recovery exponents to use (first num_missing)
        @used_recovery_exponents = recovery_exponents.first(num_missing)

        # Build A matrix: A[i,j] = base[missing[j]]^exponent[i]
        # This is num_missing x num_missing (SQUARE)
        a_matrix = Array.new(num_missing) { Array.new(num_missing, 0) }

        @used_recovery_exponents.each_with_index do |exponent, row|
          missing_indices.each_with_index do |idx, col|
            a_matrix[row][col] = Galois16.power(@bases[idx], exponent)
          end
        end

        # Invert A matrix using Gaussian elimination
        # Create augmented matrix [A | I]
        identity = Array.new(num_missing) do |i|
          Array.new(num_missing) do |j|
            i == j ? 1 : 0
          end
        end

        gaussian_elimination!(a_matrix, identity)

        # Store inverted matrix (now in identity position)
        # IMPORTANT: Transpose it so rows=missing_indices, cols=recovery_indices
        # This allows direct indexing: matrix[output_idx][recovery_idx]
        @matrix = identity.transpose
      end

      # Get matrix coefficient for computing missing blocks
      #
      # This returns the coefficient from A^-1 matrix that tells us how much
      # each recovery block contributes to each missing block.
      #
      # After transposition, matrix structure is:
      # - matrix[recovery_idx][output_idx] (rows=recovery, cols=missing)
      #
      # For x = A^-1 * b:
      #   x[output_idx] = sum over recovery_idx of A^-1[output_idx][recovery_idx] * b[recovery_idx]
      #
      # Due to transpose, we access as: matrix[recovery_idx][output_idx]
      #
      # @param output_idx [Integer] Output block index (0..missing_count-1)
      # @param recovery_idx [Integer] Recovery block index (0..recovery_count-1)
      # @return [Integer] Galois field coefficient
      def coefficient(output_idx, recovery_idx)
        raise "Matrix not computed - call compute! first" unless @matrix

        # After transpose, indices are swapped: @matrix[recovery_idx][output_idx]
        @matrix[recovery_idx][output_idx]
      end

      # Get coefficient for present block contribution to b vector
      #
      # Returns how much a present block contributes when building b vector.
      # This is: -base[present_idx]^exponent[recovery_idx]
      #
      # @param present_idx [Integer] Index of present data block
      # @param recovery_exponent [Integer] Recovery block exponent
      # @return [Integer] Galois field coefficient
      def present_contribution_coefficient(present_idx, recovery_exponent)
        Galois16.power(@bases[present_idx], recovery_exponent)
      end

      # Process a chunk of data: output_chunk ^= input_chunk * factor
      #
      # This is called thousands of times during repair to incrementally
      # build up each recovered block chunk by chunk.
      #
      # @param factor [Integer] Galois field multiplier (from matrix)
      # @param input_chunk [String] Input chunk data
      # @param output_block [String] Full output block (modified in place)
      # @param chunk_size [Integer] Chunk size in bytes (must be even)
      # @param output_offset [Integer] Offset within output block where to write
      def process_chunk(factor, input_chunk, output_block, chunk_size,
output_offset: 0)
        return if factor.zero? # Optimization

        num_words = chunk_size / 2

        num_words.times do |i|
          input_offset = i * 2
          block_offset = output_offset + (i * 2)

          # Read 16-bit words (little-endian)
          input_word = input_chunk.getbyte(input_offset) |
            (input_chunk.getbyte(input_offset + 1) << 8)

          output_word = output_block.getbyte(block_offset) |
            (output_block.getbyte(block_offset + 1) << 8)

          # Galois multiplication and addition (XOR)
          result = Galois16.add(output_word,
                                Galois16.multiply(input_word, factor))

          # Write back as bytes (little-endian)
          output_block.setbyte(block_offset, result & 0xFF)
          output_block.setbyte(block_offset + 1, (result >> 8) & 0xFF)
        end
      end

      # Get number of recovery blocks used
      #
      # @return [Integer] Recovery count
      def recovery_count
        recovery_exponents.size
      end

      # Get number of output blocks (missing)
      #
      # @return [Integer] Output count
      def output_count
        missing_indices.size
      end

      private

      # Perform Gaussian elimination to invert matrix
      #
      # Transforms [A | I] into [I | A^-1]
      #
      # @param left_matrix [Array<Array<Integer>>] Matrix to invert (modified)
      # @param right_matrix [Array<Array<Integer>>] Identity matrix (becomes inverse)
      def gaussian_elimination!(left_matrix, right_matrix)
        num_rows = left_matrix.size
        num_cols = left_matrix[0].size

        num_rows.times do |pivot_row|
          pivot = left_matrix[pivot_row][pivot_row]
          raise "Singular matrix at row #{pivot_row}" if pivot.zero?

          # Scale pivot row to make pivot = 1
          unless pivot == 1
            num_cols.times do |col|
              next if left_matrix[pivot_row][col].zero?

              left_matrix[pivot_row][col] =
                Galois16.divide(left_matrix[pivot_row][col], pivot)
            end

            num_cols.times do |col|
              next if right_matrix[pivot_row][col].zero?

              right_matrix[pivot_row][col] =
                Galois16.divide(right_matrix[pivot_row][col], pivot)
            end
          end

          # Eliminate column in all other rows
          num_rows.times do |row|
            next if row == pivot_row

            scale = left_matrix[row][pivot_row]
            next if scale.zero?

            if scale == 1
              num_cols.times do |col|
                next if left_matrix[pivot_row][col].zero?

                left_matrix[row][col] = Galois16.add(
                  left_matrix[row][col],
                  left_matrix[pivot_row][col],
                )
              end

              num_cols.times do |col|
                next if right_matrix[pivot_row][col].zero?

                right_matrix[row][col] = Galois16.add(
                  right_matrix[row][col],
                  right_matrix[pivot_row][col],
                )
              end
            else
              num_cols.times do |col|
                next if left_matrix[pivot_row][col].zero?

                scaled = Galois16.multiply(left_matrix[pivot_row][col], scale)
                left_matrix[row][col] =
                  Galois16.add(left_matrix[row][col], scaled)
              end

              num_cols.times do |col|
                next if right_matrix[pivot_row][col].zero?

                scaled = Galois16.multiply(right_matrix[pivot_row][col], scale)
                right_matrix[row][col] =
                  Galois16.add(right_matrix[row][col], scaled)
              end
            end
          end
        end
      end

      # Verify that A * A^-1 = Identity
      # @param a_original [Array<Array<Integer>>] Original A matrix
      # @param a_inv [Array<Array<Integer>>] Computed A^-1 matrix
      # @return [Boolean] true if verification passes
      def verify_matrix_inversion(a_original, a_inv)
        n = a_original.size

        # Compute A * A^-1
        result = Array.new(n) { Array.new(n, 0) }
        n.times do |i|
          n.times do |j|
            sum = 0
            n.times do |k|
              product = Galois16.multiply(a_original[i][k], a_inv[k][j])
              sum = Galois16.add(sum, product)
            end
            result[i][j] = sum
          end
        end

        # Check if result is identity
        n.times do |i|
          n.times do |j|
            expected = i == j ? 1 : 0
            return false if result[i][j] != expected
          end
        end

        true
      end
    end
  end

  # Verify that A * A^-1 = Identity
  #
  # @param a_original [Array<Array<Integer>>] Original A matrix
  # @param a_inv [Array<Array<Integer>>] Computed A^-1 matrix
  # @return [Boolean] true if verification passes
  def self.verify_matrix_inversion(a_original, a_inv)
    n = a_original.size

    # Compute A * A^-1
    result = Array.new(n) { Array.new(n, 0) }
    n.times do |i|
      n.times do |j|
        sum = 0
        n.times do |k|
          product = Galois16.multiply(a_original[i][k], a_inv[k][j])
          sum = Galois16.add(sum, product)
        end
        result[i][j] = sum
      end
    end

    # Check if result is identity
    n.times do |i|
      n.times do |j|
        expected = i == j ? 1 : 0
        if result[i][j] != expected
          warn "MATRIX VERIFICATION FAILED!"
          warn "  A * A^-1 at [#{i},#{j}] = 0x#{format('%04X',
                                                       result[i][j])} (expected #{expected})"
          warn "  This means Gaussian elimination produced wrong inverse!"
          return false
        end
      end
    end

    warn "Matrix verification: A * A^-1 = I ✓"
    true
  end
end

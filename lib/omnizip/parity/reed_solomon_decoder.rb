# frozen_string_literal: true

require_relative "galois16"
require_relative "par2cmdline_algorithm"

module Omnizip
  module Parity
    # Pure Reed-Solomon decoder for recovering missing blocks
    # This is algorithm-only code with no I/O dependencies
    #
    # Recovers missing blocks by solving a system of linear equations
    # using Gaussian elimination over GF(2^16)
    class ReedSolomonDecoder
      # Recover missing input blocks using available inputs and recovery blocks
      #
      # @param present_blocks [Hash<Integer, String>] Map of index => block data for present inputs
      # @param recovery_blocks [Array<Hash>] Array of recovery block info: {data: String, exponent: Integer}
      # @param missing_indices [Array<Integer>] Indices of missing input blocks to recover
      # @param block_size [Integer] Size of each block in bytes
      # @param total_inputs [Integer] Total number of input blocks (present + missing)
      # @return [Hash<Integer, String>] Map of recovered index => block data
      def self.decode(present_blocks, recovery_blocks, missing_indices,
block_size, total_inputs)
        raise ArgumentError, "Block size must be even" if block_size.odd?

        if missing_indices.empty?
          raise ArgumentError,
                "No missing blocks to recover"
        end
        if recovery_blocks.size < missing_indices.size
          raise ArgumentError,
                "Not enough recovery blocks"
        end

        # Select base values using par2cmdline algorithm (same as encoder)
        bases = Par2cmdlineAlgorithm.compute_bases(total_inputs)

        # Build and solve the matrix system
        solved_matrix = build_and_solve_matrix(
          present_blocks.keys.sort,
          missing_indices.sort,
          recovery_blocks.map { |r| r[:exponent] },
          bases,
        )

        # Reconstruct missing blocks using solved matrix
        reconstruct_missing_blocks(
          present_blocks,
          recovery_blocks,
          missing_indices,
          solved_matrix,
          block_size,
        )
      end

      # Build augmented matrix and solve using Gaussian elimination
      #
      # @param present_indices [Array<Integer>] Sorted indices of present blocks
      # @param missing_indices [Array<Integer>] Sorted indices of missing blocks
      # @param recovery_exponents [Array<Integer>] Exponents of recovery blocks
      # @param bases [Array<Integer>] Base values for all inputs
      # @return [Array<Array<Integer>>] Solved left matrix
      def self.build_and_solve_matrix(present_indices, missing_indices,
recovery_exponents, bases)
        num_present = present_indices.size
        num_missing = missing_indices.size
        recovery_exponents.size

        # We use first num_missing recovery blocks to solve for missing data
        num_rows = num_missing
        num_cols = num_present + num_missing

        # Allocate matrices
        left_matrix = Array.new(num_rows) { Array.new(num_cols, 0) }
        right_matrix = Array.new(num_rows) { Array.new(num_rows, 0) }

        # Fill matrices using first num_missing recovery blocks
        recovery_exponents.first(num_missing).each_with_index do |exponent, row|
          # Left matrix: base^exponent for present inputs, identity for missing
          present_indices.each_with_index do |idx, col|
            left_matrix[row][col] = Galois16.power(bases[idx], exponent)
          end

          # Identity block for missing data (helps in solving)
          num_missing.times do |col|
            left_matrix[row][num_present + col] = (row == col ? 1 : 0)
          end

          # Right matrix: base^exponent for missing inputs
          missing_indices.each_with_index do |idx, col|
            right_matrix[row][col] = Galois16.power(bases[idx], exponent)
          end
        end

        # Solve using Gaussian elimination
        gaussian_elimination(left_matrix, right_matrix)

        left_matrix
      end

      # Perform Gaussian elimination to solve the matrix system
      # Modifies matrices in place
      #
      # @param left_matrix [Array<Array<Integer>>] Left matrix (will be modified)
      # @param right_matrix [Array<Array<Integer>>] Right matrix (will be modified)
      def self.gaussian_elimination(left_matrix, right_matrix)
        num_rows = left_matrix.size
        num_left_cols = left_matrix[0].size
        num_right_cols = right_matrix[0].size

        # Forward elimination + back substitution
        num_rows.times do |pivot_row|
          # Get pivot value from right matrix diagonal
          pivot = right_matrix[pivot_row][pivot_row]
          raise "Singular matrix at row #{pivot_row}" if pivot.zero?

          # Scale pivot row to make pivot = 1
          unless pivot == 1
            # Scale left matrix
            num_left_cols.times do |col|
              next if left_matrix[pivot_row][col].zero?

              left_matrix[pivot_row][col] =
                Galois16.divide(left_matrix[pivot_row][col], pivot)
            end

            # Scale right matrix
            right_matrix[pivot_row][pivot_row] = 1
            ((pivot_row + 1)...num_right_cols).each do |col|
              next if right_matrix[pivot_row][col].zero?

              right_matrix[pivot_row][col] =
                Galois16.divide(right_matrix[pivot_row][col], pivot)
            end
          end

          # Eliminate column in all other rows
          num_rows.times do |row|
            next if row == pivot_row

            scale = right_matrix[row][pivot_row]
            next if scale.zero?

            if scale == 1
              # Optimization: just XOR subtract rows
              num_left_cols.times do |col|
                next if left_matrix[pivot_row][col].zero?

                left_matrix[row][col] = Galois16.add(
                  left_matrix[row][col],
                  left_matrix[pivot_row][col],
                )
              end

              (pivot_row...num_right_cols).each do |col|
                next if right_matrix[pivot_row][col].zero?

                right_matrix[row][col] = Galois16.add(
                  right_matrix[row][col],
                  right_matrix[pivot_row][col],
                )
              end
            else
              # General case: row -= pivot_row * scale
              num_left_cols.times do |col|
                next if left_matrix[pivot_row][col].zero?

                scaled = Galois16.multiply(left_matrix[pivot_row][col], scale)
                left_matrix[row][col] =
                  Galois16.add(left_matrix[row][col], scaled)
              end

              (pivot_row...num_right_cols).each do |col|
                next if right_matrix[pivot_row][col].zero?

                scaled = Galois16.multiply(right_matrix[pivot_row][col], scale)
                right_matrix[row][col] =
                  Galois16.add(right_matrix[row][col], scaled)
              end
            end
          end
        end
      end

      # Reconstruct missing blocks using solved matrix
      #
      # @param present_blocks [Hash<Integer, String>] Present input blocks
      # @param recovery_blocks [Array<Hash>] Recovery blocks with :data and :exponent
      # @param missing_indices [Array<Integer>] Indices to recover
      # @param solved_matrix [Array<Array<Integer>>] Solved coefficient matrix
      # @param block_size [Integer] Block size in bytes
      # @return [Hash<Integer, String>] Recovered blocks
      def self.reconstruct_missing_blocks(present_blocks, recovery_blocks,
missing_indices, solved_matrix, block_size)
        recovered = {}

        missing_indices.each_with_index do |missing_idx, row|
          # Initialize missing block to zeros
          recovered_block = "\x00".b * block_size

          # Add contribution from each present input block
          present_blocks.each do |present_idx, present_data|
            # Find column for this present block
            col = present_blocks.keys.sort.index(present_idx)
            factor = solved_matrix[row][col]

            next if factor.zero?

            # recovered_block ^= present_data * factor
            process_block(factor, present_data, recovered_block, block_size)
          end

          # Add contribution from each recovery block we're using
          num_present = present_blocks.size
          recovery_blocks.first(missing_indices.size).each_with_index do |recovery_info, rec_idx|
            col = num_present + rec_idx
            factor = solved_matrix[row][col]

            next if factor.zero?

            # recovered_block ^= recovery_data * factor
            process_block(factor, recovery_info[:data], recovered_block,
                          block_size)
          end

          recovered[missing_idx] = recovered_block
        end

        recovered
      end

      # Core operation: output_block ^= input_block * factor (in GF(2^16))
      # Same as encoder's process_block
      #
      # @param factor [Integer] Galois field multiplier
      # @param input_block [String] Input data
      # @param output_block [String] Output data (modified in place)
      # @param block_size [Integer] Block size in bytes
      def self.process_block(factor, input_block, output_block, block_size)
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

      private_class_method :build_and_solve_matrix, :gaussian_elimination,
                           :reconstruct_missing_blocks, :process_block
    end
  end
end

# frozen_string_literal: true

require_relative "galois_field"

module Omnizip
  module Parity
    # Reed-Solomon encoder/decoder for PAR2 parity blocks
    #
    # Implements systematic Reed-Solomon codes over GF(2^16) for
    # error correction in PAR2 archives.
    #
    # @example Generate parity blocks
    #   rs = ReedSolomon.new(block_size: 16384)
    #   data_blocks = read_file_blocks('file.dat')
    #   parity_blocks = rs.encode(data_blocks, num_parity: 10)
    #
    # @example Recover corrupted data
    #   rs = ReedSolomon.new(block_size: 16384)
    #   recovered = rs.decode(data_blocks, parity_blocks, erasures: [2, 5])
    class ReedSolomon
      # @return [Integer] Block size in bytes
      attr_reader :block_size

      # @return [GaloisField] Galois field instance
      attr_reader :field

      # Initialize Reed-Solomon encoder/decoder
      #
      # @param block_size [Integer] Size of each block in bytes
      # @param field_power [Integer] Galois field power (16 for PAR2)
      def initialize(block_size: 16384, field_power: 16)
        @block_size = block_size
        @field = GaloisField.new(field_power)
        @generator_cache = {}
      end

      # Encode data blocks to generate parity blocks
      #
      # @param data_blocks [Array<String>] Data blocks to protect
      # @param num_parity [Integer] Number of parity blocks to generate
      # @return [Array<String>] Generated parity blocks
      def encode(data_blocks, num_parity:)
        validate_blocks(data_blocks)

        # Generate generator polynomial for this parity count
        generator = generator_polynomial(num_parity)

        # Create parity blocks
        parity_blocks = Array.new(num_parity) { "\x00" * @block_size }

        # Process each data block
        data_blocks.each_with_index do |data_block, block_idx|
          # Convert block to field elements (16-bit words)
          elements = block_to_elements(data_block)

          # Calculate contribution to each parity block
          num_parity.times do |parity_idx|
            parity_elements = elements_to_parity(
              elements,
              block_idx,
              parity_idx,
              generator
            )

            # XOR contribution into parity block
            parity_blocks[parity_idx] = xor_blocks(
              parity_blocks[parity_idx],
              elements_to_block(parity_elements)
            )
          end
        end

        parity_blocks
      end

      # Decode and recover data using parity blocks
      #
      # @param data_blocks [Array<String, nil>] Data blocks (nil for missing)
      # @param parity_blocks [Array<String>] Parity blocks
      # @param erasures [Array<Integer>] Indices of known missing blocks
      # @return [Array<String>] Recovered data blocks
      def decode(data_blocks, parity_blocks, erasures: [])
        # Ensure we have enough parity to recover
        if erasures.size > parity_blocks.size
          raise "Cannot recover: #{erasures.size} missing blocks, " \
                "only #{parity_blocks.size} parity blocks available"
        end

        # Build syndrome matrix
        syndromes = calculate_syndromes(data_blocks, parity_blocks)

        # If all syndromes are zero, no errors
        return data_blocks if syndromes.all?(&:zero?)

        # Use erasure decoding if we know error locations
        if erasures.any?
          recover_erasures(data_blocks, parity_blocks, erasures)
        else
          # Use error detection if locations unknown
          detect_and_recover_errors(data_blocks, parity_blocks, syndromes)
        end
      end

      private

      # Validate that all blocks are correct size
      #
      # @param blocks [Array<String>] Blocks to validate
      # @raise [ArgumentError] if blocks are wrong size
      def validate_blocks(blocks)
        blocks.each_with_index do |block, idx|
          next if block.nil?

          if block.bytesize != @block_size
            raise ArgumentError,
                  "Block #{idx} size mismatch: " \
                  "#{block.bytesize} != #{@block_size}"
          end
        end
      end

      # Convert byte block to 16-bit field elements
      #
      # @param block [String] Binary block data
      # @return [Array<Integer>] Array of 16-bit elements
      def block_to_elements(block)
        elements = []
        (0...block.bytesize).step(2) do |i|
          # Combine two bytes into 16-bit element (little-endian)
          low_byte = block.getbyte(i)
          high_byte = i + 1 < block.bytesize ? block.getbyte(i + 1) : 0
          elements << (high_byte << 8) | low_byte
        end
        elements
      end

      # Convert field elements back to byte block
      #
      # @param elements [Array<Integer>] 16-bit field elements
      # @return [String] Binary block data
      def elements_to_block(elements)
        bytes = []
        elements.each do |element|
          bytes << (element & 0xFF)        # Low byte
          bytes << ((element >> 8) & 0xFF) # High byte
        end
        bytes.pack("C*")
      end

      # XOR two blocks together
      #
      # @param block1 [String] First block
      # @param block2 [String] Second block
      # @return [String] XOR result
      def xor_blocks(block1, block2)
        result = block1.bytes
        block2.bytes.each_with_index do |byte, idx|
          result[idx] ^= byte
        end
        result.pack("C*")
      end

      # Generate parity contribution for a data block
      #
      # @param elements [Array<Integer>] Data block elements
      # @param block_idx [Integer] Data block index
      # @param parity_idx [Integer] Parity block index
      # @param generator [Array<Integer>] Generator polynomial
      # @return [Array<Integer>] Parity contribution
      def elements_to_parity(elements, block_idx, parity_idx, generator)
        # Calculate exponent for this block/parity combination
        # Uses Vandermonde matrix approach
        exponent = (block_idx * (parity_idx + 1)) % (@field.size - 1)
        coefficient = @field.power(@field.generator, exponent)

        # Multiply each element by coefficient
        elements.map do |element|
          @field.multiply(element, coefficient)
        end
      end

      # Generate Reed-Solomon generator polynomial
      #
      # @param num_parity [Integer] Number of parity symbols
      # @return [Array<Integer>] Generator polynomial coefficients
      def generator_polynomial(num_parity)
        # Cache generator polynomials
        return @generator_cache[num_parity] if @generator_cache[num_parity]

        # Start with g(x) = 1
        gen = [1]

        # Multiply by (x - alpha^i) for i = 0 to num_parity-1
        num_parity.times do |i|
          root = @field.power(@field.generator, i)
          gen = polynomial_multiply(gen, [1, root])
        end

        @generator_cache[num_parity] = gen
      end

      # Multiply two polynomials in GF(2^16)
      #
      # @param poly1 [Array<Integer>] First polynomial
      # @param poly2 [Array<Integer>] Second polynomial
      # @return [Array<Integer>] Product polynomial
      def polynomial_multiply(poly1, poly2)
        result = Array.new(poly1.size + poly2.size - 1, 0)

        poly1.each_with_index do |coef1, i|
          poly2.each_with_index do |coef2, j|
            product = @field.multiply(coef1, coef2)
            result[i + j] = @field.add(result[i + j], product)
          end
        end

        result
      end

      # Calculate syndrome polynomials
      #
      # @param data_blocks [Array<String, nil>] Data blocks
      # @param parity_blocks [Array<String>] Parity blocks
      # @return [Array<Integer>] Syndrome values
      def calculate_syndromes(data_blocks, parity_blocks)
        num_parity = parity_blocks.size
        syndromes = Array.new(num_parity, 0)

        # Calculate syndrome for each parity position
        num_parity.times do |i|
          syndrome = 0

          # Contribution from data blocks
          data_blocks.each_with_index do |block, idx|
            next if block.nil?

            elements = block_to_elements(block)
            exponent = (idx * (i + 1)) % (@field.size - 1)
            coefficient = @field.power(@field.generator, exponent)

            elements.each do |element|
              syndrome = @field.add(syndrome, @field.multiply(element, coefficient))
            end
          end

          # Contribution from parity blocks
          if parity_blocks[i]
            parity_elements = block_to_elements(parity_blocks[i])
            parity_elements.each do |element|
              syndrome = @field.add(syndrome, element)
            end
          end

          syndromes[i] = syndrome
        end

        syndromes
      end

      # Recover missing blocks using erasure decoding
      #
      # @param data_blocks [Array<String, nil>] Data blocks with erasures
      # @param parity_blocks [Array<String>] Parity blocks
      # @param erasures [Array<Integer>] Indices of missing blocks
      # @return [Array<String>] Recovered data blocks
      def recover_erasures(data_blocks, parity_blocks, erasures)
        # Create working copy
        recovered = data_blocks.dup

        # Build coefficient matrix for erasures
        matrix = build_recovery_matrix(erasures, parity_blocks.size)

        # Invert matrix
        inv_matrix = invert_matrix(matrix)

        # Solve for missing blocks
        erasures.each_with_index do |missing_idx, eq_idx|
          recovered_elements = Array.new(@block_size / 2, 0)

          # Calculate each element of the missing block
          (0...(@block_size / 2)).each do |elem_idx|
            value = 0

            # Sum contributions from known blocks
            data_blocks.each_with_index do |block, block_idx|
              next if erasures.include?(block_idx) || block.nil?

              elements = block_to_elements(block)
              coefficient = inv_matrix[eq_idx][block_idx]
              value = @field.add(
                value,
                @field.multiply(elements[elem_idx], coefficient)
              )
            end

            # Add parity contributions
            parity_blocks.each_with_index do |parity, parity_idx|
              elements = block_to_elements(parity)
              coefficient = inv_matrix[eq_idx][data_blocks.size + parity_idx]
              value = @field.add(
                value,
                @field.multiply(elements[elem_idx], coefficient)
              )
            end

            recovered_elements[elem_idx] = value
          end

          recovered[missing_idx] = elements_to_block(recovered_elements)
        end

        recovered
      end

      # Build recovery matrix for erasure decoding
      #
      # @param erasures [Array<Integer>] Missing block indices
      # @param num_parity [Integer] Number of parity blocks
      # @return [Array<Array<Integer>>] Coefficient matrix
      def build_recovery_matrix(erasures, num_parity)
        matrix = []

        erasures.each do |missing_idx|
          row = []

          # Coefficients for each parity equation
          num_parity.times do |parity_idx|
            exponent = (missing_idx * (parity_idx + 1)) % (@field.size - 1)
            row << @field.power(@field.generator, exponent)
          end

          matrix << row
        end

        matrix
      end

      # Invert matrix over GF(2^16)
      #
      # @param matrix [Array<Array<Integer>>] Matrix to invert
      # @return [Array<Array<Integer>>] Inverted matrix
      # @raise [StandardError] if matrix is singular
      def invert_matrix(matrix)
        size = matrix.size
        return [[1]] if size == 1

        # Create augmented matrix [A | I]
        augmented = matrix.map.with_index do |row, i|
          identity_row = Array.new(size, 0)
          identity_row[i] = 1
          row + identity_row
        end

        # Gaussian elimination
        size.times do |i|
          # Find pivot
          pivot_row = i
          (i + 1...size).each do |j|
            if augmented[j][i] != 0 && augmented[pivot_row][i] == 0
              pivot_row = j
            end
          end

          # Swap rows if needed
          if pivot_row != i
            augmented[i], augmented[pivot_row] = augmented[pivot_row], augmented[i]
          end

          # Check for singular matrix
          if augmented[i][i].zero?
            raise "Matrix is singular, cannot invert"
          end

          # Scale pivot row
          pivot = augmented[i][i]
          pivot_inv = @field.inverse(pivot)
          (2 * size).times do |j|
            augmented[i][j] = @field.multiply(augmented[i][j], pivot_inv)
          end

          # Eliminate column
          size.times do |j|
            next if j == i

            factor = augmented[j][i]
            next if factor.zero?

            (2 * size).times do |k|
              product = @field.multiply(factor, augmented[i][k])
              augmented[j][k] = @field.subtract(augmented[j][k], product)
            end
          end
        end

        # Extract inverse matrix from augmented matrix
        augmented.map { |row| row[size..-1] }
      end

      # Detect and recover errors when location unknown
      #
      # @param data_blocks [Array<String>] Data blocks
      # @param parity_blocks [Array<String>] Parity blocks
      # @param syndromes [Array<Integer>] Calculated syndromes
      # @return [Array<String>] Recovered blocks
      def detect_and_recover_errors(data_blocks, parity_blocks, syndromes)
        # Find error locations using Berlekamp-Massey algorithm
        error_locator = berlekamp_massey(syndromes)

        # Find roots of error locator polynomial (Chien search)
        error_locations = chien_search(error_locator, data_blocks.size)

        # Calculate error values using Forney algorithm
        error_values = forney_algorithm(syndromes, error_locator, error_locations)

        # Apply corrections
        recovered = data_blocks.dup
        error_locations.each_with_index do |location, idx|
          if recovered[location]
            # Correct the error
            elements = block_to_elements(recovered[location])
            error_element = error_values[idx]
            elements.map! { |e| @field.subtract(e, error_element) }
            recovered[location] = elements_to_block(elements)
          end
        end

        recovered
      end

      # Berlekamp-Massey algorithm for finding error locator polynomial
      #
      # @param syndromes [Array<Integer>] Syndrome values
      # @return [Array<Integer>] Error locator polynomial
      def berlekamp_massey(syndromes)
        # Implementation of Berlekamp-Massey algorithm
        # This finds the shortest LFSR that generates the syndrome sequence

        n = syndromes.size
        c = [1] # Error locator polynomial
        b = [1] # Previous error locator polynomial
        l = 0   # Current length
        m = 1   # Distance since last length change
        b_mul = 1

        n.times do |i|
          # Calculate discrepancy
          discrepancy = syndromes[i]
          l.times do |j|
            discrepancy = @field.add(
              discrepancy,
              @field.multiply(c[j + 1], syndromes[i - j - 1])
            )
          end

          if discrepancy.zero?
            m += 1
          else
            t = c.dup

            # Adjust c polynomial
            c_len = [c.size, b.size + m].max
            c = Array.new(c_len, 0)
            t.each_with_index { |val, idx| c[idx] = val }

            factor = @field.multiply(discrepancy, @field.inverse(b_mul))
            b.each_with_index do |val, idx|
              c[idx + m] = @field.subtract(
                c[idx + m],
                @field.multiply(factor, val)
              )
            end

            if 2 * l <= i
              l = i + 1 - l
              b = t
              b_mul = discrepancy
              m = 1
            else
              m += 1
            end
          end
        end

        c
      end

      # Chien search for finding roots of error locator polynomial
      #
      # @param error_locator [Array<Integer>] Error locator polynomial
      # @param num_blocks [Integer] Total number of data blocks
      # @return [Array<Integer>] Error locations
      def chien_search(error_locator, num_blocks)
        locations = []

        # Test each possible location
        num_blocks.times do |i|
          # Evaluate polynomial at alpha^i
          value = evaluate_polynomial(error_locator, @field.power(@field.generator, i))

          # If polynomial evaluates to 0, this is an error location
          locations << i if value.zero?
        end

        locations
      end

      # Evaluate polynomial at a given point
      #
      # @param poly [Array<Integer>] Polynomial coefficients
      # @param x [Integer] Point to evaluate at
      # @return [Integer] Polynomial value
      def evaluate_polynomial(poly, x)
        result = 0
        x_power = 1

        poly.each do |coefficient|
          term = @field.multiply(coefficient, x_power)
          result = @field.add(result, term)
          x_power = @field.multiply(x_power, x)
        end

        result
      end

      # Forney algorithm for finding error values
      #
      # @param syndromes [Array<Integer>] Syndrome values
      # @param error_locator [Array<Integer>] Error locator polynomial
      # @param error_locations [Array<Integer>] Error locations
      # @return [Array<Integer>] Error values
      def forney_algorithm(syndromes, error_locator, error_locations)
        # Calculate error evaluator polynomial
        # Omega(x) = S(x) * Lambda(x) mod x^(n)
        error_evaluator = polynomial_multiply(
          syndrome_polynomial(syndromes),
          error_locator
        )[0...syndromes.size]

        # Calculate derivative of error locator
        locator_derivative = polynomial_derivative(error_locator)

        # Calculate error values
        error_locations.map do |location|
          x_inv = @field.inverse(@field.power(@field.generator, location))

          # Evaluate error evaluator at x_inv
          numerator = evaluate_polynomial(error_evaluator, x_inv)

          # Evaluate locator derivative at x_inv
          denominator = evaluate_polynomial(locator_derivative, x_inv)

          # Error value = numerator / denominator
          @field.divide(numerator, denominator)
        end
      end

      # Convert syndromes to polynomial
      #
      # @param syndromes [Array<Integer>] Syndrome values
      # @return [Array<Integer>] Syndrome polynomial
      def syndrome_polynomial(syndromes)
        syndromes
      end

      # Calculate polynomial derivative in GF(2^16)
      #
      # @param poly [Array<Integer>] Polynomial coefficients
      # @return [Array<Integer>] Derivative coefficients
      def polynomial_derivative(poly)
        # In GF(2^n), derivative drops even-power terms
        # d/dx(a_n*x^n + ... + a_1*x + a_0) = a_n*n*x^(n-1) + ... + a_1
        derivative = []
        poly.each_with_index do |coef, power|
          # In GF(2), only odd powers survive (even coefficients = 0)
          derivative << coef if power.odd?
        end
        derivative
      end

      # Multiply two polynomials
      #
      # @param poly1 [Array<Integer>] First polynomial
      # @param poly2 [Array<Integer>] Second polynomial
      # @return [Array<Integer>] Product polynomial
      def polynomial_multiply(poly1, poly2)
        result = Array.new(poly1.size + poly2.size - 1, 0)

        poly1.each_with_index do |coef1, i|
          poly2.each_with_index do |coef2, j|
            product = @field.multiply(coef1, coef2)
            result[i + j] = @field.add(result[i + j], product)
          end
        end

        result
      end
    end
  end
end
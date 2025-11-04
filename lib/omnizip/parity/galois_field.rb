# frozen_string_literal: true

module Omnizip
  module Parity
    # Galois Field GF(2^16) arithmetic for Reed-Solomon codes
    #
    # This class implements finite field arithmetic operations needed
    # for PAR2 parity calculations. GF(2^16) uses polynomial arithmetic
    # modulo an irreducible polynomial.
    #
    # @example Basic field operations
    #   gf = GaloisField.new(16)
    #   result = gf.multiply(0x1234, 0x5678)
    #   inverse = gf.divide(1, 0x1234)
    class GaloisField
      # @return [Integer] Field power (16 for GF(2^16))
      attr_reader :power

      # @return [Integer] Field size (65536 for GF(2^16))
      attr_reader :size

      # Generator polynomial for GF(2^16)
      # x^16 + x^12 + x^3 + x + 1
      GENERATOR_POLY_16 = 0x1100B

      # Initialize Galois Field
      #
      # @param power [Integer] Field power (must be 16 for PAR2)
      # @raise [ArgumentError] if power is not 16
      def initialize(power = 16)
        raise ArgumentError, "Only GF(2^16) supported" unless power == 16

        @power = power
        @size = 2**power
        @log_table = Array.new(@size)
        @exp_table = Array.new(@size * 2) # Double size for optimization

        build_tables
      end

      # Multiply two field elements
      #
      # @param a [Integer] First element (0-65535)
      # @param b [Integer] Second element (0-65535)
      # @return [Integer] Product in GF(2^16)
      def multiply(a, b)
        return 0 if a.zero? || b.zero?

        @exp_table[(@log_table[a] + @log_table[b]) % (@size - 1)]
      end

      # Divide two field elements
      #
      # @param a [Integer] Dividend
      # @param b [Integer] Divisor
      # @return [Integer] Quotient in GF(2^16)
      # @raise [ZeroDivisionError] if dividing by zero
      def divide(a, b)
        raise ZeroDivisionError, "Division by zero in GF" if b.zero?
        return 0 if a.zero?

        @exp_table[(@log_table[a] - @log_table[b] + (@size - 1)) % (@size - 1)]
      end

      # Add two field elements (XOR in GF(2^n))
      #
      # @param a [Integer] First element
      # @param b [Integer] Second element
      # @return [Integer] Sum in GF(2^16)
      def add(a, b)
        a ^ b
      end

      # Subtract two field elements (XOR in GF(2^n))
      #
      # @param a [Integer] First element
      # @param b [Integer] Second element
      # @return [Integer] Difference in GF(2^16)
      def subtract(a, b)
        a ^ b # In GF(2^n), subtraction = addition = XOR
      end

      # Raise field element to a power
      #
      # @param base [Integer] Base element
      # @param exponent [Integer] Exponent
      # @return [Integer] Result in GF(2^16)
      def power(base, exponent)
        return 1 if exponent.zero?
        return 0 if base.zero?

        # Use logarithm properties: a^b = exp(b * log(a))
        @exp_table[(exponent * @log_table[base]) % (@size - 1)]
      end

      # Find multiplicative inverse
      #
      # @param a [Integer] Element to invert
      # @return [Integer] Inverse element
      # @raise [ZeroDivisionError] if a is zero
      def inverse(a)
        raise ZeroDivisionError, "Cannot invert zero" if a.zero?

        @exp_table[(@size - 1) - @log_table[a]]
      end

      # Get generator element (primitive element alpha)
      #
      # @return [Integer] Generator element (2)
      def generator
        2
      end

      private

      # Build logarithm and exponent lookup tables
      #
      # These tables speed up multiplication and division operations
      # by converting them to addition and subtraction in log space.
      def build_tables
        # Start with generator element (alpha = 2)
        x = 1

        # Build both tables simultaneously
        (@size - 1).times do |i|
          @exp_table[i] = x
          @log_table[x] = i

          # Multiply by generator (alpha) with reduction
          x = x << 1

          # Apply reduction if we've exceeded field size
          x ^= GENERATOR_POLY_16 if x >= @size
        end

        # Extend exp_table for optimization (avoid modulo in multiply)
        (@size - 1).times do |i|
          @exp_table[i + @size - 1] = @exp_table[i]
        end
      end
    end
  end
end
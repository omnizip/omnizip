# frozen_string_literal: true

require_relative "galois16"

module Omnizip
  module Parity
    # Par2cmdline-compatible Reed-Solomon algorithm
    #
    # This implements the EXACT algorithm from par2cmdline reedsolomon.cpp
    # Lines 230-262 show the base value computation for encoding.
    #
    # Key algorithm from par2cmdline:
    #   unsigned int logbase = 0;
    #   for (unsigned int index=0; index<count; index++)
    #   {
    #     while (gcd(G::Limit, logbase) != 1)
    #     {
    #       logbase++;
    #     }
    #     G::ValueType base = G(logbase++).ALog();
    #     database[index] = base;
    #   }
    #
    # Then for matrix: coefficient = base[col] ^ exponent
    #
    module Par2cmdlineAlgorithm
      # Compute base values exactly as par2cmdline does
      #
      # @param data_count [Integer] Number of data blocks
      # @return [Array<Integer>] Base values for each data block
      def self.compute_bases(data_count)
        bases = []
        logbase = 0
        limit = 65535 # GF(2^16) limit

        data_count.times do
          # Find next logbase where gcd(65535, logbase) == 1
          logbase += 1 while gcd(limit, logbase) != 1

          raise "Too many input blocks" if logbase >= limit

          # Use antilog to convert logbase to base value
          # This is the key: base = antilog[logbase]
          base = Galois16.antilog(logbase)
          bases << base
          logbase += 1
        end

        bases
      end

      # Build encoding matrix using par2cmdline algorithm
      #
      # @param data_count [Integer] Number of data blocks
      # @param recovery_count [Integer] Number of recovery blocks
      # @return [Array<Array<Integer>>] Encoding matrix
      def self.build_encoding_matrix(data_count, recovery_count)
        bases = compute_bases(data_count)

        matrix = Array.new(recovery_count) { Array.new(data_count) }

        recovery_count.times do |exponent|
          data_count.times do |col|
            # Matrix coefficient = base[col] ^ exponent
            matrix[exponent][col] = Galois16.power(bases[col], exponent)
          end
        end

        matrix
      end

      # Compute greatest common divisor
      #
      # @param a [Integer]
      # @param b [Integer]
      # @return [Integer] GCD of a and b
      def self.gcd(a, b)
        return 0 if a.zero? && b.zero?
        return a + b if a.zero? || b.zero?

        while a.positive? && b.positive?
          if a > b
            a %= b
          else
            b %= a
          end
        end

        a + b
      end

      # Verify algorithm by generating expected coefficients
      #
      # @param max_exponent [Integer] Maximum exponent to test
      # @return [Hash<Integer, Integer>] Coefficient for each exponent
      def self.generate_coefficient_table(max_exponent = 100)
        bases = compute_bases(10) # Test with 10 data blocks
        coefficients = {}

        (0..max_exponent).each do |exponent|
          # For par2cmdline, ALL data blocks use the same coefficient
          # which is base[0] ^ exponent
          coefficients[exponent] = Galois16.power(bases[0], exponent)
        end

        coefficients
      end
    end
  end
end

# frozen_string_literal: true

module Omnizip
  module Parity
    # Pure implementation of Galois Field GF(2^16) arithmetic
    # Uses generator polynomial 0x1100B (69643) as per PAR2 specification
    #
    # This is pure algorithm code with no I/O dependencies.
    # All operations are exact (no floating point) and work in GF(2^16).
    class Galois16
      BITS = 16
      GENERATOR = 0x1100B # 69643 in decimal
      FIELD_SIZE = 1 << BITS # 65536
      LIMIT = FIELD_SIZE - 1 # 65535

      # Lookup tables for efficient operations
      @log_table = nil
      @antilog_table = nil

      class << self
        # Build log and antilog tables
        # This is called once when the class is loaded
        def build_tables
          return if @log_table && @antilog_table

          @log_table = Array.new(FIELD_SIZE)
          @antilog_table = Array.new(FIELD_SIZE)

          b = 1
          LIMIT.times do |l|
            @log_table[b] = l
            @antilog_table[l] = b

            b <<= 1
            b ^= GENERATOR if b.anybits?(FIELD_SIZE)
          end

          # Special cases for zero
          @log_table[0] = LIMIT
          @antilog_table[LIMIT] = 0
        end

        # Get log value (discrete logarithm)
        def log(value)
          @log_table[value & 0xFFFF]
        end

        # Get antilog value (inverse of log)
        def antilog(value)
          @antilog_table[value % FIELD_SIZE]
        end

        # Addition in GF(2^16) - same as subtraction (XOR)
        def add(a, b)
          (a ^ b) & 0xFFFF
        end

        # Subtraction in GF(2^16) - same as addition (XOR)
        alias subtract add

        # Multiplication in GF(2^16)
        def multiply(a, b)
          a &= 0xFFFF
          b &= 0xFFFF

          return 0 if a.zero? || b.zero?

          sum = @log_table[a] + @log_table[b]
          sum -= LIMIT if sum >= LIMIT
          @antilog_table[sum]
        end

        # Division in GF(2^16)
        def divide(a, b)
          a &= 0xFFFF
          b &= 0xFFFF

          return 0 if a.zero?
          raise ArgumentError, "Division by zero in GF(2^16)" if b.zero?

          diff = @log_table[a] - @log_table[b]
          diff += LIMIT if diff.negative?
          @antilog_table[diff]
        end

        # Power in GF(2^16): compute a^n
        def power(a, n)
          a &= 0xFFFF

          return 1 if n.zero?
          return 0 if a.zero?

          product = @log_table[a] * n

          # Reduce modulo LIMIT using the identity:
          # product mod LIMIT = (product >> BITS) + (product & LIMIT)
          product = (product >> BITS) + (product & LIMIT)
          product -= LIMIT if product >= LIMIT

          @antilog_table[product]
        end

        # Compute GCD using Euclidean algorithm
        def gcd(a, b)
          while a != 0 && b != 0
            if a > b
              a %= b
            else
              b %= a
            end
          end
          a + b
        end

        # Select base values for Reed-Solomon matrix
        # Par2cmdline uses sequential logbases: base[i] = antilog[i]
        # base[0] = antilog[0] = 1, base[1] = antilog[1] = 2, etc.
        def select_bases(count)
          raise ArgumentError, "Too many bases requested" if count >= LIMIT

          bases = []

          count.times do |i|
            # Par2cmdline uses logbase = i (NOT i+1!)
            # This gives: base[0]=1, base[1]=2, base[2]=4, etc.
            logbase = i

            if logbase >= LIMIT
              raise ArgumentError,
                    "Too many input blocks for Reed Solomon matrix"
            end

            # Convert log to actual value
            bases << @antilog_table[logbase]
          end

          bases
        end
      end

      # Build tables when class is loaded
      build_tables
    end
  end
end

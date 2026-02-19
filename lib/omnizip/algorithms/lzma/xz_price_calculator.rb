# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # XZ Utils-compatible price calculator
      #
      # Calculates the cost (in price units) of encoding symbols using
      # probability models. Prices are based on logarithmic probabilities:
      # price = -log2(probability) * scale_factor
      #
      # Uses precomputed tables for efficiency, matching XZ Utils exactly.
      #
      # Based on: xz/src/liblzma/rangecoder/price.h
      class XzPriceCalculator
        include Constants

        # Price scale factor (matches XZ Utils)
        PRICE_SHIFT_BITS = 4
        PRICE_SCALE = 1 << PRICE_SHIFT_BITS

        # BIT_MODEL_TOTAL = 2^11 = 2048 (from Constants, but define locally for clarity)
        BIT_MODEL_TOTAL_LOCAL = 0x800
        BIT_MODEL_TOTAL_BITS = 11

        # Number of entries in price table
        PRICE_TABLE_SIZE = BIT_MODEL_TOTAL_LOCAL >> PRICE_SHIFT_BITS

        class << self
          # Calculate price for encoding a single bit
          #
          # @param prob [Integer] Probability model value (0..BIT_MODEL_TOTAL)
          # @param bit [Integer] Bit value (0 or 1)
          # @return [Integer] Price in price units
          def bit_price(prob, bit)
            if bit.zero?
              # Price for encoding 0
              PRICE_TABLE[prob >> PRICE_SHIFT_BITS]
            else
              # Price for encoding 1
              PRICE_TABLE[(BIT_MODEL_TOTAL_LOCAL - prob) >> PRICE_SHIFT_BITS]
            end
          end

          # Calculate price for encoding a symbol using bit tree
          #
          # A bit tree encodes a symbol by encoding its bits from MSB to LSB,
          # using probability models indexed by the partial symbol value.
          #
          # @param probs [Array<BitModel>] Probability models for tree
          # @param num_bits [Integer] Number of bits in symbol
          # @param symbol [Integer] Symbol value to encode
          # @return [Integer] Total price in price units
          def bittree_price(probs, num_bits, symbol)
            price = 0
            symbol |= (1 << num_bits) # Add sentinel bit

            # Encode bits from MSB to LSB
            (num_bits - 1).downto(0) do |i|
              bit = (symbol >> i) & 1
              model_idx = symbol >> (i + 1)
              price += bit_price(probs[model_idx].probability, bit)
            end

            price
          end

          # Calculate price for encoding a symbol using reverse bit tree
          #
          # A reverse bit tree encodes a symbol by encoding its bits from
          # LSB to MSB, used for distance encoding.
          #
          # @param probs [Array<BitModel>] Probability models for tree
          # @param num_bits [Integer] Number of bits in symbol
          # @param symbol [Integer] Symbol value to encode
          # @return [Integer] Total price in price units
          def bittree_reverse_price(probs, num_bits, symbol)
            price = 0
            model_idx = 1

            # Encode bits from LSB to MSB
            num_bits.times do |i|
              bit = (symbol >> i) & 1
              price += bit_price(probs[model_idx].probability, bit)
              model_idx = (model_idx << 1) | bit
            end

            price
          end

          # Calculate price for direct bits (uniform distribution)
          #
          # Direct bits have no probability model, each bit costs the same.
          #
          # @param num_bits [Integer] Number of direct bits
          # @return [Integer] Total price in price units
          def direct_price(num_bits)
            # Each direct bit costs 64 units (price of 0.5 probability)
            num_bits << (PRICE_SHIFT_BITS + 2)
          end

          # Precompute logarithmic price table using Math.log2
          #
          # Generates a table mapping probabilities to prices using the formula:
          # price[i] = -log2(i / BIT_MODEL_TOTAL) * PRICE_SCALE
          #
          # @return [Array<Integer>] Precomputed price table
          def precompute_price_table
            table = Array.new(PRICE_TABLE_SIZE)

            PRICE_TABLE_SIZE.times do |i|
              if i.zero?
                # Handle zero probability case (maximum price)
                table[i] = 15 << PRICE_SHIFT_BITS
              else
                # Reconstruct probability from table index
                prob = (i << PRICE_SHIFT_BITS) + (PRICE_SCALE >> 1)
                probability = prob.to_f / BIT_MODEL_TOTAL_LOCAL

                # price = -log2(probability) * PRICE_SCALE
                price = (-Math.log2(probability) * PRICE_SCALE).round
                table[i] = price
              end
            end

            table
          end
        end

        # Precomputed logarithmic price table
        # Each entry represents -log2(i/BIT_MODEL_TOTAL) * PRICE_SCALE
        PRICE_TABLE = precompute_price_table.freeze

        # Instance methods for convenience

        # @param prob [Integer] Probability value
        # @param bit [Integer] Bit value
        # @return [Integer] Price
        def bit_price(prob, bit)
          self.class.bit_price(prob, bit)
        end

        # @param probs [Array<BitModel>] Probability models
        # @param num_bits [Integer] Number of bits
        # @param symbol [Integer] Symbol value
        # @return [Integer] Price
        def bittree_price(probs, num_bits, symbol)
          self.class.bittree_price(probs, num_bits, symbol)
        end

        # @param probs [Array<BitModel>] Probability models
        # @param num_bits [Integer] Number of bits
        # @param symbol [Integer] Symbol value
        # @return [Integer] Price
        def bittree_reverse_price(probs, num_bits, symbol)
          self.class.bittree_reverse_price(probs, num_bits, symbol)
        end

        # @param num_bits [Integer] Number of direct bits
        # @return [Integer] Price
        def direct_price(num_bits)
          self.class.direct_price(num_bits)
        end
      end
    end
  end
end

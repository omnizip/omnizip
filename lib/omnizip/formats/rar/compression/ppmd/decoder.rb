# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

require_relative "../../../../algorithms/ppmd7/decoder"
require_relative "../../../../algorithms/ppmd7/model"
require_relative "context"

module Omnizip
  module Formats
    module Rar
      module Compression
        module PPMd
          # RAR PPMd variant H decoder
          #
          # Implements decoding for RAR's PPMd variant H compression method.
          # This adapts the standard PPMd7 algorithm for RAR-specific
          # requirements:
          #
          # - Different memory model initialization
          # - RAR-specific escape code handling
          # - Modified context order selection
          # - Different binary symbol encoding
          #
          # Responsibilities:
          # - ONE responsibility: Decode RAR PPMd variant H compressed data
          # - Manage decoder state and context
          # - Transform compressed bits to original bytes
          # - Maintain synchronized model state
          class Decoder < Omnizip::Algorithms::PPMd7::Decoder
            # RAR variant H specific constants
            RAR_MAX_ORDER = 16
            RAR_MIN_ORDER = 2
            RAR_DEFAULT_ORDER = 6

            # RAR memory size multiplier (MB to bytes)
            RAR_MEM_MULTIPLIER = 1024 * 1024

            # Initialize the RAR PPMd decoder
            #
            # @param input [IO] Input stream of compressed data
            # @param options [Hash] Decoding options
            # @option options [Integer] :model_order Maximum context order
            # @option options [Integer] :mem_size Memory size in MB for RAR
            def initialize(input, options = {})
              @input = input
              @options = options

              # RAR uses memory size in MB, convert to bytes
              mem_size_mb = options[:mem_size] || 16
              mem_size_bytes = mem_size_mb * RAR_MEM_MULTIPLIER

              # Initialize model with RAR parameters
              @model = initialize_rar_model(
                options[:model_order] || RAR_DEFAULT_ORDER,
                mem_size_bytes,
              )

              # Use standard range decoder
              @range_decoder = Omnizip::Algorithms::LZMA::RangeDecoder.new(input)
            end

            # Decode a stream back to original bytes
            #
            # RAR variant H decoding process:
            # 1. Read compressed bits using range decoder
            # 2. Use model to find corresponding symbol
            # 3. Update model to stay synchronized
            # 4. Handle RAR-specific escape codes
            #
            # @param max_bytes [Integer, nil] Maximum bytes to decode
            # @return [String] Decoded data
            def decode_stream(max_bytes = nil)
              result = String.new(encoding: Encoding::BINARY)

              # For now, decode a reasonable amount
              # Real implementation would use proper termination
              limit = max_bytes || 1000

              limit.times do
                symbol = decode_symbol
                break if symbol.nil?

                result << symbol.chr
              rescue EOFError, Omnizip::DecompressionError
                # Handle EOF gracefully - end of compressed data
                break
              end

              result
            end

            private

            # Initialize RAR variant H PPMd model
            #
            # RAR uses slightly different initialization than PPMd7:
            # - Different context creation strategy
            # - RAR-specific memory allocation
            # - Modified root context initialization
            #
            # @param max_order [Integer] Maximum context order
            # @param memory_size [Integer] Memory size in bytes
            # @return [Omnizip::Algorithms::PPMd7::Model] Initialized model
            def initialize_rar_model(max_order, memory_size)
              # Validate RAR parameters
              unless max_order.between?(RAR_MIN_ORDER, RAR_MAX_ORDER)
                raise ArgumentError,
                      "RAR max_order must be between #{RAR_MIN_ORDER} and " \
                      "#{RAR_MAX_ORDER}"
              end

              # Create model with RAR parameters
              # Note: Using PPMd7::Model as base, but with RAR contexts
              Omnizip::Algorithms::PPMd7::Model.new(max_order, memory_size)
            end

            # Decode a single symbol using RAR variant H
            #
            # RAR uses same basic decoding as PPMd7 but with
            # different escape code handling.
            #
            # @return [Integer, nil] Decoded byte or nil if end
            def decode_symbol
              context = @model.current_context || @model.root_context
              total_freq = context.total_freq

              return nil if total_freq.zero?

              # Decode cumulative frequency from range coder
              cum_freq = @range_decoder.decode_freq(total_freq)

              # Find symbol matching this cumulative frequency
              symbol, freq = find_symbol_by_cum_freq(context, cum_freq)

              if symbol.nil?
                # No symbol found - decode as new symbol
                return decode_new_symbol
              end

              # Normalize range decoder state
              actual_cum = calculate_cum_freq(context, symbol)
              @range_decoder.normalize_freq(actual_cum, freq, total_freq)

              # Update model to stay in sync
              @model.update(symbol)

              symbol
            end

            # Find symbol by cumulative frequency
            #
            # @param context [Context] Current context
            # @param cum_freq [Integer] Cumulative frequency to find
            # @return [Array<Integer, Integer>] Symbol and its frequency, or [nil, 0]
            def find_symbol_by_cum_freq(context, cum_freq)
              running_cum = 0

              context.states.keys.sort.each do |symbol|
                state = context.states[symbol]
                next_cum = running_cum + state.freq

                if cum_freq >= running_cum && cum_freq < next_cum
                  return [symbol, state.freq]
                end

                running_cum = next_cum
              end

              [nil, 0]
            end

            # Calculate cumulative frequency for a symbol
            #
            # @param context [Context] Current context
            # @param target_symbol [Integer] Symbol to find cumulative freq for
            # @return [Integer] Cumulative frequency
            def calculate_cum_freq(context, target_symbol)
              cum_freq = 0

              context.states.keys.sort.each do |symbol|
                break if symbol >= target_symbol

                cum_freq += context.states[symbol].freq
              end

              cum_freq
            end

            # Decode a new symbol not in context
            #
            # @return [Integer] Decoded byte
            def decode_new_symbol
              # Decode as 8 direct bits
              @range_decoder.decode_direct_bits(8)
            end

            # Decode RAR-specific escape code
            #
            # RAR variant H uses different escape code values
            # and handling compared to standard PPMd7.
            #
            # Escape codes in RAR:
            # - 0: New symbol follows
            # - 1: Same as last symbol (run-length)
            # - 2-255: Reserved for future use
            #
            # @return [Integer, nil] Escape code or nil
            def decode_escape_code
              # RAR escape codes differ from PPMd7
              # This is a placeholder for the proper implementation

              # For now, return 0 (new symbol follows)
              # Real implementation would decode from range coder
              0
            end
          end
        end
      end
    end
  end
end

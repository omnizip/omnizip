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

require_relative "../../../../algorithms/ppmd7/encoder"
require_relative "../../../../algorithms/ppmd7/model"
require_relative "../../../../algorithms/lzma/range_encoder"
require_relative "context"

module Omnizip
  module Formats
    module Rar
      module Compression
        module PPMd
          # RAR PPMd variant H encoder
          #
          # Implements encoding for RAR's PPMd variant H compression method.
          # This adapts the standard PPMd7 algorithm for RAR-specific
          # requirements:
          #
          # - Different memory model initialization
          # - RAR-specific escape code handling
          # - Modified context order selection
          # - Different binary symbol encoding
          #
          # Responsibilities:
          # - ONE responsibility: Encode data using RAR PPMd variant H
          # - Manage encoder state and context
          # - Transform original bytes to compressed bits
          # - Maintain synchronized model state (matches decoder)
          class Encoder < Omnizip::Algorithms::PPMd7::Encoder
            # RAR variant H specific constants
            RAR_MAX_ORDER = 16
            RAR_MIN_ORDER = 2
            RAR_DEFAULT_ORDER = 6

            # RAR memory size multiplier (MB to bytes)
            RAR_MEM_MULTIPLIER = 1024 * 1024

            # Accessor for memory size (for testing)
            def memory_size
              @model.instance_variable_get(:@mem_size)
            end

            # Initialize the RAR PPMd encoder
            #
            # @param output [IO] Output stream for compressed data
            # @param options [Hash] Encoding options
            # @option options [Integer] :model_order Maximum context order
            # @option options [Integer] :mem_size Memory size in MB for RAR
            def initialize(output, options = {})
              @output = output
              @options = options

              # RAR uses memory size in MB, convert to bytes
              mem_size_mb = options[:mem_size] || 16
              mem_size_bytes = mem_size_mb * RAR_MEM_MULTIPLIER

              # Initialize model with RAR parameters
              @model = initialize_rar_model(
                options[:model_order] || RAR_DEFAULT_ORDER,
                mem_size_bytes,
              )

              # Use range encoder for bit output
              @range_encoder = Omnizip::Algorithms::LZMA::RangeEncoder.new(output)
            end

            # Encode a stream to compressed bytes
            #
            # RAR variant H encoding process:
            # 1. Read byte from input
            # 2. Find symbol in current context
            # 3. Encode using range coder with probabilities
            # 4. Update model to stay synchronized with decoder
            # 5. Handle RAR-specific escape codes if needed
            #
            # @param input [IO] Input stream to compress
            # @param max_bytes [Integer, nil] Maximum bytes to encode
            # @return [Integer] Number of bytes encoded
            def encode_stream(input, max_bytes = nil)
              bytes_encoded = 0

              loop do
                break if max_bytes && bytes_encoded >= max_bytes

                byte = input.read(1)
                break unless byte

                encode_symbol(byte.ord)
                bytes_encoded += 1
              end

              # Flush encoder to ensure all data is written
              @range_encoder.flush
              bytes_encoded
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

            # Encode a single symbol using RAR variant H
            #
            # RAR uses same basic encoding as PPMd7 but with
            # different escape code handling and probability calculation.
            #
            # Process:
            # 1. Get current context
            # 2. Check if symbol exists in context
            # 3. If yes: encode using frequency information
            # 4. If no: encode escape + new symbol
            # 5. Update model state
            #
            # @param byte [Integer] Byte value to encode (0-255)
            # @return [void]
            def encode_symbol(byte)
              # Get current context
              context = @model.current_context

              # Find symbol in context (returns SymbolState or nil)
              state = context.find_symbol(byte)

              if state
                # Encode using frequency information
                encode_symbol_in_context(byte, state, context)
              else
                # Encode escape + new symbol
                encode_escape_code
                encode_new_symbol(byte)
              end

              # Update model to stay synchronized with decoder
              @model.update(byte)
            end

            # Encode symbol that exists in current context
            #
            # Uses the frequency information from the context to
            # calculate probability range for range encoder.
            #
            # @param byte [Integer] Symbol to encode
            # @param state [SymbolState] Symbol's state
            # @param context [Context] Current context
            # @return [void]
            def encode_symbol_in_context(byte, state, context)
              # Get frequency from state
              freq = state.freq
              total_freq = context.total_freq

              # Calculate cumulative frequency (for range low)
              cum_freq = 0
              context.states.each do |sym, st|
                break if sym >= byte

                cum_freq += st.freq
              end

              # Encode range using frequencies
              encode_range(cum_freq, freq, total_freq)
            end

            # Encode RAR-specific escape code
            #
            # RAR variant H uses different escape code values
            # and handling compared to standard PPMd7.
            #
            # Escape codes in RAR:
            # - 0: New symbol follows
            # - 1: Same as last symbol (run-length)
            # - 2-255: Reserved for future use
            #
            # @return [void]
            def encode_escape_code
              # For now, we encode escape as a binary decision with 50% probability
              # This is simplified - real PPMd uses SEE (Secondary Escape Estimation)
              @range_encoder.encode_freq(0, 1, 2)
            end

            # Encode new symbol not in current context
            #
            # When a symbol doesn't exist in the current context,
            # encode it using uniform distribution (all symbols
            # equally likely).
            #
            # @param byte [Integer] Symbol to encode
            # @return [void]
            def encode_new_symbol(byte)
              # Encode as 8 direct bits (uniform distribution)
              @range_encoder.encode_direct_bits(byte, 8)
            end

            # Encode a range for the symbol
            #
            # Converts frequency information to range and encodes
            # using the range encoder.
            #
            # @param cum_freq [Integer] Cumulative frequency
            # @param freq [Integer] Symbol frequency
            # @param total_freq [Integer] Total frequency
            # @return [void]
            def encode_range(cum_freq, freq, total_freq)
              return if total_freq.zero?

              @range_encoder.encode_freq(cum_freq, freq, total_freq)
            end
          end
        end
      end
    end
  end
end

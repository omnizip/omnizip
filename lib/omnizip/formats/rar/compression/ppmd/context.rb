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

require_relative "../../../../algorithms/ppmd7/context"

module Omnizip
  module Formats
    module Rar
      module Compression
        module PPMd
          # RAR variant H context node in PPMd model
          #
          # Adapts PPMd7 Context for RAR-specific requirements:
          # - Different memory allocation strategy
          # - RAR-specific escape frequency initialization
          # - Modified probability update rules
          #
          # Responsibilities:
          # - ONE responsibility: Manage RAR PPMd variant H context
          # - Track symbol statistics for RAR compression
          # - Maintain context tree structure
          # - Handle RAR-specific probability updates
          class Context < Omnizip::Algorithms::PPMd7::Context
            # RAR variant H escape frequency constant
            # RAR uses different initial escape frequency than PPMd7
            RAR_INIT_ESCAPE_FREQ = 1

            # Initialize a new RAR variant H context
            #
            # @param order [Integer] The order of this context (depth in tree)
            # @param suffix [Context, nil] Parent context (shorter context)
            def initialize(order, suffix = nil)
              super
              # RAR variant H uses different escape frequency initialization
              @escape_freq = RAR_INIT_ESCAPE_FREQ
            end

            # Update symbol frequency after encoding/decoding (RAR variant)
            #
            # RAR variant H uses a slightly different update strategy
            # compared to standard PPMd7.
            #
            # @param symbol [Integer] The symbol to update
            # @param increment [Integer] Amount to increase frequency
            # @return [void]
            def update_symbol(symbol, increment = 1)
              state = @states[symbol]
              return unless state

              # RAR variant H frequency update
              state.freq += increment
              @sum_freq += increment

              # RAR uses different rescaling threshold
              rescale_frequencies if @sum_freq > rar_max_freq
            end

            private

            # RAR variant H maximum frequency threshold
            #
            # @return [Integer] Maximum frequency before rescaling
            def rar_max_freq
              # RAR uses 124 as maximum frequency (same as PPMd7)
              124
            end

            # Rescale frequencies when they grow too large (RAR variant)
            #
            # RAR variant H uses same rescaling strategy as PPMd7
            # but this method is here for future RAR-specific modifications.
            #
            # @return [void]
            def rescale_frequencies
              @sum_freq = 0
              @states.each_value do |state|
                state.freq = [(state.freq + 1) / 2, 1].max
                @sum_freq += state.freq
              end
            end
          end
        end
      end
    end
  end
end

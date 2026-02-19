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

require_relative "xz_utils_decoder"

module Omnizip
  module Algorithms
    class LZMA < Algorithm
      # LZMA Decoder - Factory for LZMA decompression implementations
      #
      # This class provides a unified interface for LZMA decoding, delegating
      # to the XZ Utils implementation for full compatibility.
      #
      # The decoder reads a stream that consists of:
      # - Property byte (lc, lp, pb parameters)
      # - Dictionary size (4 bytes)
      # - Uncompressed size (8 bytes)
      # - Compressed data
      class Decoder
        attr_reader :dict_size, :lc, :lp, :pb, :uncompressed_size

        # Initialize the decoder
        #
        # @param input [IO] Input stream of compressed data
        # @param options [Hash] Decoding options
        # @option options [Boolean] :raw_mode Skip header parsing for raw LZMA (for LZMA2)
        # @option options [Integer] :dict_size Dictionary size for raw mode
        def initialize(input, options = {})
          # Use XZ Utils LZMA decoder (full XZ Utils compatibility)
          @impl = XzUtilsDecoder.new(input, options)

          # Expose header info for backward compatibility
          @lc = @impl.lc
          @lp = @impl.lp
          @pb = @impl.pb
          @dict_size = @impl.dict_size
          @uncompressed_size = @impl.uncompressed_size
        end

        # Decode a compressed stream
        #
        # @param output [IO, nil] Optional output stream (if nil, returns String)
        # @param preserve_dict [Boolean] Whether to preserve dictionary from previous decode
        # @return [String, Integer] Decompressed data or bytes written
        def decode_stream(output = nil, preserve_dict: false)
          @impl.decode_stream(output, preserve_dict: preserve_dict)
        end

        # Reset the decoder state for reuse with new properties
        #
        # This method is used by LZMA2 decoder for multi-chunk streams.
        #
        # @param new_lc [Integer, nil] New lc value (if nil, keeps current)
        # @param new_lp [Integer, nil] New lp value (if nil, keeps current)
        # @param new_pb [Integer, nil] New pb value (if nil, keeps current)
        # @param preserve_dict [Boolean] If true, preserve dictionary state (pos, dict_full)
        # @return [void]
        def reset(new_lc: nil, new_lp: nil, new_pb: nil, preserve_dict: false)
          @impl.reset(new_lc: new_lc, new_lp: new_lp, new_pb: new_pb,
                      preserve_dict: preserve_dict)

          # Update cached properties
          @lc = @impl.lc
          @lp = @impl.lp
          @pb = @impl.pb
        end

        # Reset only state machine and rep distances, preserve probability models
        #
        # This method is used by LZMA2 decoder for multi-chunk streams.
        #
        # @return [void]
        def reset_state_only
          @impl.reset_state_only
        end

        # Prepare state reset - called BEFORE setting new input
        #
        # This method is used by LZMA2 decoder for multi-chunk streams.
        #
        # @return [void]
        def prepare_state_reset
          @impl.prepare_state_reset
        end

        # Reset state machine only - preserves rep distances
        #
        # This method is used by LZMA2 decoder for multi-chunk streams
        # where we want to reset the state machine but preserve rep distances
        # from the previous chunk (control >= 0xA0 but < 0xC0).
        #
        # @return [void]
        def reset_state_machine_only
          @impl.reset_state_machine_only
        end

        # Finish state reset - called AFTER setting new input
        #
        # This method is used by LZMA2 decoder for multi-chunk streams.
        #
        # @return [void]
        def finish_state_reset
          @impl.finish_state_reset
        end

        # Set new input stream for chunked decoding
        #
        # This method is used by LZMA2 decoder for multi-chunk streams.
        #
        # @param new_input [IO] New input stream
        # @return [void]
        def set_input(new_input)
          @impl.set_input(new_input)
        end

        # Set uncompressed size for chunked decoding
        #
        # This method is used by LZMA2 decoder for multi-chunk streams.
        #
        # @param size [Integer] Uncompressed size
        # @param allow_eopm [Boolean] Whether to allow end-of-stream marker
        # @return [void]
        def set_uncompressed_size(size, allow_eopm: true)
          @impl.set_uncompressed_size(size, allow_eopm: allow_eopm)
        end
      end
    end
  end
end

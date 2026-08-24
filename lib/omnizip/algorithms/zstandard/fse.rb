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

module Omnizip
  module Algorithms
    class Zstandard
      # FSE (Finite State Entropy) namespace (RFC 8878 §4.1).
      module FSE
        autoload :BitStream, "omnizip/algorithms/zstandard/fse/bitstream"
        autoload :Table, "omnizip/algorithms/zstandard/fse/table"
        autoload :TableDescription,
                 "omnizip/algorithms/zstandard/fse/table_description"
        autoload :Interleaved, "omnizip/algorithms/zstandard/fse/interleaved"
        autoload :Encoder, "omnizip/algorithms/zstandard/fse/encoder"

        module_function

        # Read an FSE table description from the head of `src`.
        #
        # @return [Array(Table, Integer)] table and bytes consumed
        def read_table(src)
          TableDescription.read(src)
        end

        # Decode a 2-state interleaved FSE stream.
        #
        # @return [Array<Integer>]
        def decode_stream(table, bitstream_bytes, max_output)
          Interleaved.decode_stream(table, bitstream_bytes, max_output)
        end
      end
    end
  end
end

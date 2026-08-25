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
      # Zstandard dictionary (port of the omnizip-rs dict.rs).
      #
      # A dictionary lets the encoder preload a reference-content
      # window so small inputs compress dramatically better: the
      # dictionary content is used as a match-finder prefix, and the
      # frame header carries the dictionary's ID.
      #
      # Wire format (simplified form, as in the Rust reference):
      # magic (4) + dictionary ID (4, LE) + raw content.
      class Dictionary
        DICT_MAGIC = 0xEC30A437

        attr_reader :id, :content

        # @param id [Integer] dictionary ID carried in frame headers
        # @param content [String] corpus bytes used as the prefix
        def initialize(id, content)
          @id = id
          @content = content.dup.force_encoding(Encoding::BINARY)
        end

        def self.from_raw(id, content)
          new(id, content)
        end

        def self.deserialize(data)
          if data.bytesize < 8
            raise Omnizip::DecompressionError,
                  "dictionary too short for magic + id"
          end
          if data.byteslice(0, 4).unpack1("V") != DICT_MAGIC
            raise Omnizip::DecompressionError, "bad dictionary magic"
          end

          new(data.byteslice(4, 4).unpack1("V"), data.byteslice(8..))
        end

        def serialize
          [DICT_MAGIC].pack("V") + [@id].pack("V") + @content
        end

        def ==(other)
          other.is_a?(Dictionary) && id == other.id && content == other.content
        end
      end
    end
  end
end

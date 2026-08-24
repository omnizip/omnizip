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
      # XXHash64 (https://github.com/Cyan4973/xxHash), single-shot.
      #
      # Zstandard frame checksums are the low 32 bits of XXHash64 of the
      # decoded content with seed 0 (the zstd C reference truncates
      # XXH64_digest to a U32; RFC 8878's "xxh64" wording agrees).
      module XXHash64
        MASK64 = 0xFFFFFFFFFFFFFFFF
        MASK32 = 0xFFFFFFFF

        PRIME64_1 = 0x9E3779B185EBCA87
        PRIME64_2 = 0xC2B2AE3D27D4EB4F
        PRIME64_3 = 0x165667B19E3779F9
        PRIME64_4 = 0x85EBCA77C2B2AE63
        PRIME64_5 = 0x27D4EB2F165667C5

        module_function

        # Digest `data` with seed 0.
        #
        # @param data [String] binary string
        # @return [Integer] 64-bit digest
        def digest(data)
          digest_seeded(data, 0)
        end

        def digest_seeded(data, seed)
          len = data.bytesize
          hash = 0
          tail_start = 0

          if len >= 32
            v1 = (seed + PRIME64_1 + PRIME64_2) & MASK64
            v2 = (seed + PRIME64_2) & MASK64
            v3 = seed & MASK64
            v4 = (seed - PRIME64_1) & MASK64

            i = 0
            while i + 32 <= len
              v1 = round64(v1, read_u64(data, i))
              v2 = round64(v2, read_u64(data, i + 8))
              v3 = round64(v3, read_u64(data, i + 16))
              v4 = round64(v4, read_u64(data, i + 24))
              i += 32
            end

            hash = rotl64(v1, 1)
            hash = (hash + rotl64(v2, 7)) & MASK64
            hash = (hash + rotl64(v3, 12)) & MASK64
            hash = (hash + rotl64(v4, 18)) & MASK64

            hash = merge_round64(hash, v1)
            hash = merge_round64(hash, v2)
            hash = merge_round64(hash, v3)
            hash = merge_round64(hash, v4)

            tail_start = len - (len % 32)
          else
            hash = (seed + PRIME64_5) & MASK64
          end

          hash = (hash + len) & MASK64

          i = tail_start
          while i + 8 <= len
            k1 = round64(0, read_u64(data, i))
            hash ^= k1
            hash = ((rotl64(hash, 27) * PRIME64_1) & MASK64) + PRIME64_4
            hash &= MASK64
            i += 8
          end
          if i + 4 <= len
            hash ^= (read_u32(data, i) * PRIME64_1) & MASK64
            hash = ((rotl64(hash, 23) * PRIME64_2) & MASK64) + PRIME64_3
            hash &= MASK64
            i += 4
          end
          while i < len
            hash ^= (data.getbyte(i) * PRIME64_5) & MASK64
            hash = (rotl64(hash, 11) * PRIME64_1) & MASK64
            i += 1
          end

          hash ^= hash >> 33
          hash = (hash * PRIME64_2) & MASK64
          hash ^= hash >> 29
          hash = (hash * PRIME64_3) & MASK64
          hash ^= hash >> 32
          hash
        end

        # Zstandard frame checksum: low 32 bits of XXHash64.
        #
        # @return [Integer] 32-bit checksum
        def frame_checksum(data)
          digest(data) & MASK32
        end

        def read_u64(data, offset)
          data.getbyte(offset) |
            (data.getbyte(offset + 1) << 8) |
            (data.getbyte(offset + 2) << 16) |
            (data.getbyte(offset + 3) << 24) |
            (data.getbyte(offset + 4) << 32) |
            (data.getbyte(offset + 5) << 40) |
            (data.getbyte(offset + 6) << 48) |
            (data.getbyte(offset + 7) << 56)
        end

        def read_u32(data, offset)
          data.getbyte(offset) |
            (data.getbyte(offset + 1) << 8) |
            (data.getbyte(offset + 2) << 16) |
            (data.getbyte(offset + 3) << 24)
        end

        def rotl64(value, count)
          ((value << count) | (value >> (64 - count))) & MASK64
        end

        def round64(acc, input)
          acc = ((acc + (input * PRIME64_2)) & MASK64) & MASK64
          acc = rotl64(acc, 31)
          (acc * PRIME64_1) & MASK64
        end

        def merge_round64(acc, value)
          value = round64(0, value)
          acc ^= value
          (((acc * PRIME64_1) & MASK64) + PRIME64_4) & MASK64
        end
      end
    end
  end
end

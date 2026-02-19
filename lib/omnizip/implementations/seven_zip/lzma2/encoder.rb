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

require "stringio"
require_relative "../../base/lzma2_encoder_base"
require_relative "../../../algorithms/lzma2/constants"
require_relative "../../../algorithms/lzma2/lzma2_chunk"

module Omnizip
  module Implementations
    module SevenZip
      module LZMA2
        # 7-Zip SDK LZMA2 encoder implementation.
        #
        # This encoder produces LZMA2 compressed data compatible with 7-Zip format.
        # It uses the same LZMA encoding logic as XZ Utils, but with 7-Zip
        # format requirements (no EOS marker, no padding).
        #
        # Key differences from XZ Utils implementation:
        # - No EOS marker (raw LZMA2 data ends with 0x00 control byte)
        # - No chunk padding (XZ pads to 4-byte boundary)
        # - No LZMA2 property byte in data stream (method ID only in container)
        #
        # Based on LZMA SDK by Igor Pavlov
        # Reference: https://www.7-zip.org/sdk.html
        #
        # LZMA2 format (as used by 7-Zip):
        # - Control byte specifies chunk type and dictionary reset
        # - Dictionary size follows in some chunk types
        # - Uncompressed size follows in some chunk types
        # - Compressed data follows
        class Encoder < Base::LZMA2EncoderBase
          include Omnizip::Algorithms::LZMA2Const

          # Maximum chunk sizes (from LZMA2 specification)
          MAX_UNCOMPRESSED_CHUNK = 2 * 1024 * 1024 # 2MB
          MAX_COMPRESSED_CHUNK = 64 * 1024 # 64KB

          # Encoding constants
          UINT32_MAX = 0xFFFFFFFF
          REPS = 4
          MATCH_LEN_MIN = 2

          attr_reader :dict_size, :lc, :lp, :pb, :standalone

          # Initialize 7-Zip SDK LZMA2 encoder
          #
          # @param dict_size [Integer] Dictionary size (must be power of 2)
          # @param lc [Integer] Literal context bits (0-8)
          # @param lp [Integer] Literal position bits (0-4)
          # @param pb [Integer] Position bits (0-4)
          # @param standalone [Boolean] Include property byte (false for 7-Zip)
          def initialize(dict_size:, lc: 3, lp: 0, pb: 2, standalone: false)
            super

            # Initialize shared state across all chunks
            # Using XZ Utils components (tested and working)
            require_relative "../../../algorithms/lzma/dictionary"
            require_relative "../../../algorithms/lzma/lzma_state"
            require_relative "../../../algorithms/lzma/xz_probability_models"
            require_relative "../../../algorithms/lzma/match_finder"
            require_relative "../../../algorithms/lzma/optimal_encoder"
            require_relative "../../../algorithms/lzma/xz_range_encoder_exact"

            @dictionary = Omnizip::Algorithms::LZMA::Dictionary.new(dict_size)
            @state = Omnizip::Algorithms::LZMA::LZMAState.new(0)
            @models = Omnizip::Algorithms::LZMA::XzProbabilityModels.new(lc, lp, pb)
            @match_finder = Omnizip::Algorithms::LZMA::MatchFinder.new(@dictionary)
            @optimal = Omnizip::Algorithms::LZMA::OptimalEncoder.new(mode: :fast)

            # Track previous byte for literal context
            @prev_byte = 0

            # First chunk always resets dictionary (7-Zip compatibility)
            @need_dictionary_reset = true
            @need_state_reset = false
            @need_properties = true
          end

          # Encode data with LZMA2 compression
          #
          # @param data [String] Input data to compress
          # @return [String] LZMA2 compressed data (7-Zip format)
          def encode(data)
            return "" if data.empty?

            output = StringIO.new
            output.set_encoding(Encoding::BINARY)

            # Write property byte if standalone mode
            if @standalone
              prop_byte = encode_dict_size(@dict_size)
              output.putc(prop_byte)
            end

            # Reset match finder state for each encoding session
            @match_finder.reset

            # Process in chunks
            input = StringIO.new(data)
            input.set_encoding(Encoding::BINARY)

            while !input.eof?
              chunk_data = input.read(MAX_UNCOMPRESSED_CHUNK)
              break if chunk_data.nil? || chunk_data.empty?

              chunk = encode_chunk(chunk_data)
              output.write(chunk)

              # Update reset flags for next chunk
              @need_dictionary_reset = false
              @need_state_reset = false
              @need_properties = false
            end

            # End of stream marker (0x00)
            output.write(Omnizip::Algorithms::LZMA2::LZMA2Chunk.end_chunk.to_bytes)

            output.string
          end

          # Get implementation identifier
          #
          # @return [Symbol] :seven_zip_sdk
          def implementation_name
            :seven_zip_sdk
          end

          private

          # Encode a single chunk with LZMA2 compression
          #
          # Uses XZ Utils encoding logic (tested and compatible)
          def encode_chunk(uncompressed_data)
            compressed = try_compress(uncompressed_data)

            # Decide: compressed vs uncompressed
            # Use compressed if it's actually smaller
            if compressed.bytesize >= uncompressed_data.bytesize
              # Use uncompressed chunk
              chunk = Omnizip::Algorithms::LZMA2::LZMA2Chunk.new(
                chunk_type: :uncompressed,
                uncompressed_data: uncompressed_data,
                compressed_data: "",
                need_dict_reset: @need_dictionary_reset,
                need_state_reset: false,
                need_props: false,
              )
              # After uncompressed chunk, next chunk needs state reset
              @need_state_reset = true
            else
              # Use compressed chunk
              chunk_properties = (((@pb * 5) + @lp) * 9) + @lc
              chunk = Omnizip::Algorithms::LZMA2::LZMA2Chunk.new(
                chunk_type: :compressed,
                uncompressed_data: uncompressed_data,
                compressed_data: compressed,
                compressed_size: compressed.bytesize,
                properties: chunk_properties,
                need_dict_reset: @need_dictionary_reset,
                need_state_reset: @need_state_reset,
                need_props: true,
              )
            end

            # Update dictionary with the chunk data
            @dictionary.append(uncompressed_data)

            # Update prev_byte for next chunk
            if uncompressed_data.bytesize.positive?
              @prev_byte = uncompressed_data.getbyte(uncompressed_data.bytesize - 1)
            end

            chunk.to_bytes
          end

          # Try to compress data using LZMA
          #
          # Uses XZ Utils encoding components (tested and working)
          def try_compress(data)
            # Create output buffer
            output_buffer = StringIO.new
            output_buffer.set_encoding(Encoding::BINARY)

            # Create range encoder
            encoder = Omnizip::Algorithms::LZMA::XzRangeEncoder.new(output_buffer)

            # Feed all data to match finder first
            @match_finder.feed(data)

            # Initialize hash table
            match_len_max = 2
            end_pos = [@dictionary.buffer.bytesize + data.bytesize - match_len_max, 0].max
            @match_finder.skip(end_pos)

            # Position in match finder's buffer for encoding
            start_pos = @dictionary.buffer.bytesize
            @current_start_pos = start_pos

            pos = 0
            while pos < data.bytesize
              # Encode queued symbols if buffer getting full
              if encoder.count > 20
                encode_queued_symbols(encoder, output_buffer)
              end

              # Find matches at current position
              match_pos = start_pos + pos
              @match_finder.find_matches(match_pos)

              # Get optimal encoding choice
              distance, length = @optimal.find_optimal(
                match_pos,
                @match_finder,
                @state,
                @state.reps,
                @models,
              )

              # Encode based on choice
              if distance == UINT32_MAX || length == 1
                encode_literal(data.getbyte(pos), encoder, pos)
                pos += 1
              elsif distance < REPS
                encode_repeated_match(distance, length, encoder, pos, match_pos)
                pos += length
              else
                actual_distance = distance - REPS
                encode_match(actual_distance, length, encoder, pos, match_pos, data)
                pos += length
              end
            end

            # Flush encoder
            encode_queued_symbols(encoder, output_buffer)
            encoder.queue_flush
            encode_queued_symbols(encoder, output_buffer)

            output_buffer.string
          end

          # Encode queued symbols to output
          def encode_queued_symbols(encoder, output)
            return if encoder.none?

            temp_buffer = "\0" * 10000
            out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)

            size_before = output.size

            encoder.encode_symbols(temp_buffer, out_pos, 10000)

            if out_pos.value.positive?
              output.write(StringCompat.byteslice(temp_buffer, 0, out_pos.value))
            end

            output.size - size_before
          end

          # Compatibility helper for Ruby 3.0-3.1
          module StringCompat
            if "".respond_to?(:byteslice)
              def self.byteslice(string, start, length)
                string.byteslice(start, length)
              end
            else
              def self.byteslice(string, start, length)
                string.bytes[start, length]&.pack("C*") || ""
              end
            end
          end

          # Encode literal byte
          def encode_literal(symbol, encoder, pos)
            pos_state = pos & ((1 << @pb) - 1)

            prob_is_match = @models.is_match[@state.value][pos_state]
            encoder.queue_bit(prob_is_match, 0)

            literal_offset = get_literal_state(pos, @prev_byte)
            use_matched = @state.use_matched_literal?

            @state.update_literal!

            if use_matched
              match_pos = @current_start_pos + pos
              match_byte_pos = match_pos - @state.reps[0] - 1
              match_byte = @match_finder.buffer.getbyte(match_byte_pos) if match_byte_pos >= 0 && match_byte_pos < @match_finder.buffer.bytesize

              if match_byte.nil?
                encode_normal_literal(literal_offset, symbol, encoder)
              else
                encode_matched_literal(literal_offset, match_byte, symbol, encoder)
              end
            else
              encode_normal_literal(literal_offset, symbol, encoder)
            end

            @prev_byte = symbol
          end

          # Encode normal match
          def encode_match(distance, length, encoder, pos, match_pos, _input_data)
            pos_state = pos & ((1 << @pb) - 1)

            prob_is_match = @models.is_match[@state.value][pos_state]
            encoder.queue_bit(prob_is_match, 1)

            prob_is_rep = @models.is_rep[@state.value]
            encoder.queue_bit(prob_is_rep, 0)

            @state.update_match!(distance)

            encode_match_length(length, pos_state, encoder)
            encode_distance(distance, length, encoder)

            last_byte_pos = match_pos - distance + length - 1
            @prev_byte = @match_finder.buffer.getbyte(last_byte_pos) if last_byte_pos >= 0 && last_byte_pos < @match_finder.buffer.bytesize
          end

          # Encode repeated match
          def encode_repeated_match(rep, length, encoder, pos, match_pos)
            pos_state = pos & ((1 << @pb) - 1)

            prob_is_match = @models.is_match[@state.value][pos_state]
            encoder.queue_bit(prob_is_match, 1)

            prob_is_rep = @models.is_rep[@state.value]
            encoder.queue_bit(prob_is_rep, 1)

            prob_is_rep0 = @models.is_rep0[@state.value]
            if rep.zero?
              encoder.queue_bit(prob_is_rep0, 0)

              prob_is_rep0_long = @models.is_rep0_long[@state.value][pos_state]
              encoder.queue_bit(prob_is_rep0_long, length == 1 ? 0 : 1)
            else
              encoder.queue_bit(prob_is_rep0, 1)

              prob_is_rep1 = @models.is_rep1[@state.value]
              if rep == 1
                encoder.queue_bit(prob_is_rep1, 0)
              else
                encoder.queue_bit(prob_is_rep1, 1)

                prob_is_rep2 = @models.is_rep2[@state.value]
                encoder.queue_bit(prob_is_rep2, rep - 2)

                if rep == 3
                  @state.reps[3] = @state.reps[2]
                end

                @state.reps[2] = @state.reps[1]
              end

              @state.reps[1] = @state.reps[0]

              distance = @state.reps[rep]

              if distance.nil?
                raise "Distance is nil for rep #{rep}, reps=#{@state.reps.inspect}"
              end

              @state.reps[0] = distance
            end

            if length == 1
              @state.update_short_rep!
            else
              encode_match_length(length, pos_state, encoder)
              @state.update_long_rep!
            end

            last_byte_pos = match_pos - @state.reps[0] + length - 1
            @prev_byte = @match_finder.buffer.getbyte(last_byte_pos) if last_byte_pos >= 0 && last_byte_pos < @match_finder.buffer.bytesize
          end

          def get_literal_state(pos, prev_byte)
            literal_mask = (0x100 << @lp) - (0x100 >> @lc)
            ((((pos << 8) + prev_byte) & literal_mask) << @lc)
          end

          def encode_normal_literal(literal_offset, symbol, encoder)
            context = 1
            8.downto(1) do |i|
              bit = (symbol >> (i - 1)) & 1
              encoder.queue_bit(@models.literal[literal_offset + context], bit)
              context = (context << 1) | bit
            end
          end

          def encode_matched_literal(literal_offset, match_byte, symbol, encoder)
            offset = 0x100
            symbol += 0x100

            while symbol < 0x10000
              match_byte <<= 1
              match_bit = match_byte & offset
              subcoder_index = offset + match_bit + (symbol >> 8)
              bit = (symbol >> 7) & 1

              encoder.queue_bit(@models.literal[literal_offset + subcoder_index], bit)

              symbol <<= 1
              offset &= ~(match_byte ^ symbol)
            end
          end

          def encode_match_length(length, pos_state, encoder)
            len = length - 2

            if len < 8
              encoder.queue_bit(@models.match_len_encoder.choice, 0)
              encode_bittree(@models.match_len_encoder.low[pos_state], 3, len, encoder)
            elsif len < 16
              encoder.queue_bit(@models.match_len_encoder.choice, 1)
              encoder.queue_bit(@models.match_len_encoder.choice2, 0)
              encode_bittree(@models.match_len_encoder.mid[pos_state], 3, len - 8, encoder)
            else
              encoder.queue_bit(@models.match_len_encoder.choice, 1)
              encoder.queue_bit(@models.match_len_encoder.choice2, 1)
              encode_bittree(@models.match_len_encoder.high, 8, len - 16, encoder)
            end
          end

          def encode_distance(distance, length, encoder)
            dist_slot = get_dist_slot(distance)
            len_state = [length - 2, 3].min

            encode_bittree(@models.dist_slot[len_state], 6, dist_slot, encoder)

            if dist_slot >= 4
              footer_bits = (dist_slot >> 1) - 1
              base = (2 | (dist_slot & 1)) << footer_bits
              dist_reduced = distance - base

              if dist_slot < 14
                encode_bittree_reverse(@models.dist_special, dist_reduced, footer_bits, base - dist_slot - 1, encoder)
              else
                direct_bits = footer_bits - 4
                encoder.queue_direct_bits(dist_reduced >> 4, direct_bits)
                align_mask = (1 << 4) - 1
                encode_bittree_reverse(@models.dist_align, dist_reduced & align_mask, 4, 0, encoder)
              end
            end
          end

          def encode_bittree(probs, num_bits, value, encoder)
            context = 1
            num_bits.downto(1) do |i|
              bit = (value >> (i - 1)) & 1
              encoder.queue_bit(probs[context], bit)
              context = (context << 1) | bit
            end
          end

          def encode_bittree_reverse(probs, value, num_bits, offset, encoder)
            context = 1
            num_bits.times do |i|
              bit = (value >> i) & 1
              encoder.queue_bit(probs[offset + context], bit)
              context = (context << 1) | bit
            end
          end

          def get_dist_slot(distance)
            if distance < 4
              distance
            else
              slot = 0
              dist = distance
              while dist > 3
                dist >>= 1
                slot += 2
              end
              slot + dist
            end
          end

          def encode_dict_size(dict_size)
            d = [dict_size, DICT_SIZE_MIN].max

            log2_size = 0
            temp = d
            while temp > 1
              log2_size += 1
              temp >>= 1
            end

            if d == (1 << log2_size)
              [(log2_size - 12) * 2, 40].min
            else
              [((log2_size - 12) * 2) + 1, 40].min
            end
          end
        end
      end
    end
  end
end

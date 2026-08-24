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

module Omnizip
  module Implementations
    module XZUtils
      module LZMA2
        # XZ Utils LZMA2 encoder implementation.
        #
        # This is the original XzLZMA2Encoder moved from algorithms/lzma2/xz_lzma2_encoder.rb
        # to the new namespace structure.
        #
        # Ported from XZ Utils liblzma/lzma2_encoder.c
        #
        # Compatibility helper for Ruby 3.0-3.1 where String#byteslice doesn't exist
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

        # Constants
        UINT32_MAX = 0xFFFFFFFF
        REPS = 4

        # XZ Utils LZMA2 encoder.
        class Encoder < Base::LZMA2EncoderBase
          include Omnizip::Algorithms::LZMA::Constants

          # XZ Utils limits (from lzma2_encoder.h)
          # Maximum UNCOMPRESSED size per chunk: 2MB
          UNCOMPRESSED_MAX = 1 << 21 # 2,097,152 bytes
          # Maximum COMPRESSED size per chunk: 64KB
          COMPRESSED_MAX = 1 << 16 # 65,536 bytes
          # Uncompressed chunks store their size in a 16-bit field,
          # so each uncompressed chunk is also limited to 64KB.
          UNCOMPRESSED_CHUNK_MAX = 1 << 16

          # Initialize the encoder
          # @param options [Hash] Encoding options
          # @option options [Integer] :dict_size Dictionary size (default: 8MB)
          # @option options [Integer] :lc Literal context bits (default: 3)
          # @option options [Integer] :lp Literal position bits (default: 0)
          # @option options [Integer] :pb Position bits (default: 2)
          # @option options [Boolean] :standalone If true, write property byte at start (default: true)
          def initialize(options = {})
            dict_size = options.fetch(:dict_size, 8 * 1024 * 1024)
            lc = options.fetch(:lc, 3)
            lp = options.fetch(:lp, 0)
            pb = options.fetch(:pb, 2)
            standalone = options.fetch(:standalone, true)

            super(
              dict_size: dict_size,
              lc: lc,
              lp: lp,
              pb: pb,
              standalone: standalone
            )

            # Shared state across all chunks
            @dictionary = Omnizip::Algorithms::LZMA::Dictionary.new(dict_size)
            @state = Omnizip::Algorithms::LZMA::LZMAState.new(0)
            @models = Omnizip::Algorithms::LZMA::XzProbabilityModels.new(lc,
                                                                         lp, pb)
            @match_finder = Omnizip::Algorithms::LZMA::MatchFinder.new(@dictionary)
            @optimal = Omnizip::Algorithms::LZMA::OptimalEncoder.new(mode: :fast)

            # Track previous byte for literal context
            @prev_byte = 0

            # CRITICAL: For XZ Utils compatibility, first chunk MUST reset the dictionary
            # (matches XZ Utils behavior - see lzma2_encoder.c:334-336)
            # need_dictionary_reset is set to true for the first compressed chunk
            @need_state_reset = false
            @need_dictionary_reset = true # Always reset dictionary for first chunk (XZ Utils compatibility)
          end

          def encode(input_data)
            # CRITICAL: Reset match finder state for each encoding session
            # This ensures hash table and hash chain start fresh for each Xz.create call
            @match_finder.reset

            output = StringIO.new
            output.set_encoding(Encoding::BINARY)

            # Write property byte if standalone mode (for .lz2 files)
            # The property byte encodes dictionary size
            if @standalone
              output.putc(encode_dict_size(@dict_size))
            end

            input = StringIO.new(input_data)
            input.set_encoding(Encoding::BINARY)

            # Process in chunks (UNCOMPRESSED_MAX = 2MB per chunk)
            while !input.eof?
              chunk_data = input.read(UNCOMPRESSED_MAX)
              break if chunk_data.nil? || chunk_data.empty?

              consume_chunk(chunk_data, output)
            end

            # End marker (0x00) is REQUIRED for all LZMA2 streams
            # The @standalone flag only controls whether a property byte is written
            # at the START (for raw LZMA2 format like .lz2), not the end marker.
            # XZ format requires the end marker to properly terminate the LZMA2 stream.
            output.write([0x00].pack("C"))

            output.string
          end

          # Get implementation identifier.
          #
          # @return [Symbol] :xz_utils
          def implementation_name
            :xz_utils
          end

          private

          # Encode chunk_data (<= UNCOMPRESSED_MAX bytes), emitting one or
          # more LZMA2 chunks.
          #
          # Multiple chunks are required when the compressed output reaches
          # COMPRESSED_MAX (the compressed size is stored in a 16-bit field)
          # or when compression is not beneficial and the data must be
          # stored as uncompressed chunks (each capped at 64KB).
          def consume_chunk(chunk_data, output)
            @match_finder.feed(chunk_data)
            @match_finder.skip(@match_finder.buffer.bytesize)

            offset = 0
            while offset < chunk_data.bytesize
              slice = chunk_data.byteslice(offset, chunk_data.bytesize - offset)

              # A state reset must apply BEFORE encoding the chunk that
              # announces it (0xC0/0xE0 control byte), so that the encoder's
              # models match the decoder's from the chunk's first bit.
              reset_lzma_state! if @need_state_reset || @need_dictionary_reset

              compressed, consumed = try_compress(slice)

              use_compressed =
                consumed.positive? &&
                compressed.bytesize <= COMPRESSED_MAX &&
                compressed.bytesize < (consumed == slice.bytesize ? slice.bytesize : consumed)

              if use_compressed
                uncompressed = chunk_data.byteslice(offset, consumed)
                emit_compressed_chunk(output, uncompressed, compressed)

                offset += consumed
                @need_state_reset = false
              else
                # Compression didn't help (or hit the cap immediately):
                # store the whole slice as uncompressed chunks.
                emit_uncompressed_chunks(output, slice)

                offset += slice.bytesize
                # After an uncompressed chunk the LZMA state is lost, so the
                # next compressed chunk must reset it (XZ Utils behavior,
                # lzma2_encoder.c).
                @need_state_reset = true
              end
              @need_dictionary_reset = false
            end

            # Update prev_byte for next chunk
            if chunk_data.bytesize.positive?
              @prev_byte = chunk_data.getbyte(chunk_data.bytesize - 1)
            end
          end

          # Reset the LZMA state machine and probability models.
          #
          # MUST be called before encoding any chunk whose control byte
          # announces a state reset (0xC0/0xE0), because the decoder will
          # reinitialize its models on seeing that byte.
          def reset_lzma_state!
            @state = Omnizip::Algorithms::LZMA::LZMAState.new(0)
            @models = Omnizip::Algorithms::LZMA::XzProbabilityModels.new(@lc,
                                                                         @lp,
                                                                         @pb)
            @prev_byte = 0
          end

          # Emit a compressed LZMA2 chunk.
          def emit_compressed_chunk(output, uncompressed, compressed)
            # For compressed chunks, properties encode lc/lp/pb:
            # (pb * 5 + lp) * 9 + lc
            chunk_properties = (((@pb * 5) + @lp) * 9) + @lc

            # A dictionary reset implies a state reset; props accompany
            # every state reset (control 0xE0 or 0xC0).
            state_reset = @need_state_reset || @need_dictionary_reset

            chunk = Omnizip::Algorithms::LZMA2::LZMA2Chunk.new(
              chunk_type: :compressed,
              uncompressed_data: uncompressed,
              compressed_data: compressed,
              compressed_size: compressed.bytesize,
              properties: chunk_properties,
              need_dict_reset: @need_dictionary_reset,
              need_state_reset: state_reset,
              need_props: state_reset,
            )
            output.write(chunk.to_bytes)

            # Update dictionary with the chunk data
            @dictionary.append(uncompressed)
          end

          # Emit uncompressed LZMA2 chunks for data (splitting at the
          # 64KB per-chunk limit imposed by the 16-bit size field).
          def emit_uncompressed_chunks(output, data)
            offset = 0
            while offset < data.bytesize
              slice = data.byteslice(offset, UNCOMPRESSED_CHUNK_MAX)
              chunk = Omnizip::Algorithms::LZMA2::LZMA2Chunk.new(
                chunk_type: :uncompressed,
                uncompressed_data: slice,
                compressed_data: "",
                need_dict_reset: @need_dictionary_reset,
                need_state_reset: false,
                need_props: false,
              )
              output.write(chunk.to_bytes)
              @need_dictionary_reset = false

              offset += slice.bytesize
              @dictionary.append(slice)
            end
          end

          # Compress data starting at the current dictionary position.
          #
          # Stops early (returning fewer bytes than data.bytesize) when the
          # compressed output is about to exceed COMPRESSED_MAX, leaving the
          # range encoder at a clean item boundary.
          #
          # @return [Array<String, Integer>] compressed bytes and number of
          #   input bytes consumed
          def try_compress(data)
            # Create output buffer to capture compressed data
            output_buffer = StringIO.new
            output_buffer.set_encoding(Encoding::BINARY)

            # Create range encoder (direct XZ Utils port)
            encoder = Omnizip::Algorithms::LZMA::XzRangeEncoder.new(output_buffer)

            # The whole chunk has already been fed to the match finder by
            # consume_chunk; positions map from the dictionary position.
            start_pos = @dictionary.buffer.bytesize

            # Headroom for pending symbols plus the final flush
            size_cap = COMPRESSED_MAX - 64

            pos = 0
            while pos < data.bytesize
              # Drain before every item: a single worst-case match (long
              # length + dist slot >= 14 with up to 30 footer bits) queues
              # ~48 symbols, and RC_SYMBOLS_MAX is 53, so the queue MUST be
              # empty when an item starts or `bit` raises "Symbol buffer
              # overflow" (issue #26).
              encode_queued_symbols(encoder, output_buffer)

              # Enforce the 64KB compressed-chunk cap at an item boundary
              break if pos.positive? && output_buffer.size >= size_cap

              # Position in match finder's buffer for encoding
              match_pos = start_pos + pos

              # Get optimal encoding choice
              # Note: find_optimal calls find_matches internally, no need to call twice
              distance, length = @optimal.find_optimal(
                match_pos,
                @match_finder,
                @state,
                @state.reps,
                @models,
              )

              # DEBUG: Trace encoding decisions
              puts "[DEBUG] pos=#{pos} distance=#{distance} length=#{length} state=#{@state.value} reps=#{@state.reps.inspect}" if ENV["DEBUG"]

              # Encode based on choice
              # CRITICAL: Use UINT32_MAX to check for literal (not distance.zero?)
              # because distance=0 means repeated match rep0, not literal!
              if distance == UINT32_MAX || length == 1
                # Encode literal. The position argument must be GLOBAL
                # (dictionary position), because the decoder keeps counting
                # bytes across chunk boundaries for pos_state.
                encode_literal(data.getbyte(pos), encoder, match_pos)
                pos += 1
              elsif distance < REPS
                # Encode repeated match (distance is 0-3 for rep0-rep3)
                encode_repeated_match(distance, length, encoder, match_pos,
                                      match_pos)
                pos += length
              else
                # Encode normal match (distance is actual_distance + REPS)
                actual_distance = distance - REPS
                encode_match(actual_distance, length, encoder, match_pos,
                             match_pos, data)
                pos += length
              end
            end

            # Flush encoder to write remaining bytes
            # IMPORTANT: Encode all pending symbols FIRST, before queue_flush
            encode_queued_symbols(encoder, output_buffer)

            # Now flush the encoder (adds 5 RC_FLUSH symbols)
            encoder.queue_flush

            # Encode the flush symbols
            # This will write additional bytes to output_buffer
            encode_queued_symbols(encoder, output_buffer)

            [output_buffer.string, pos]
          end

          # Encode queued symbols to output
          def encode_queued_symbols(encoder, output)
            return if encoder.none?

            # Create temporary buffer for encoding
            temp_buffer = "\0" * 10000
            out_pos = Omnizip::Algorithms::LZMA::IntRef.new(0)

            # Track size before encoding
            size_before = output.size

            # Encode symbols to buffer
            encoder.encode_symbols(temp_buffer, out_pos, 10000)

            # Write to output stream
            if out_pos.value.positive?
              # Use StringCompat.byteslice for Ruby 3.0-3.1 compatibility
              # Ruby's [] operator has a bug with null bytes that can return extra bytes
              # See: https://bugs.ruby-lang.org/issues/15985
              output.write(StringCompat.byteslice(temp_buffer, 0,
                                                  out_pos.value))
            end

            # Return the number of bytes written
            output.size - size_before
          end

          # Encode literal byte
          # pos is the GLOBAL position (dictionary position) because the
          # decoder counts bytes continuously across chunks.
          def encode_literal(symbol, encoder, pos)
            pos_state = pos & ((1 << @pb) - 1)

            # Encode is_match bit (0 for literal) - uses OLD state value
            prob_is_match = @models.is_match[@state.value][pos_state]
            encoder.queue_bit(prob_is_match, 0)

            # Get literal subcoder flat index (uses OLD state value via @prev_byte)
            # This is the base offset into the flat literal array
            literal_offset = get_literal_state(pos, @prev_byte)

            # CRITICAL: Check encoding path BEFORE updating state (XZ Utils order)
            # The is_literal_state check happens on the current state
            use_matched = @state.use_matched_literal?

            # Now update state (this is the update_literal() call in XZ)
            @state.update_literal!

            if use_matched
              # Matched literal (compare with match byte at rep0)
              # XZ Utils: mf->buffer[mf->read_pos - coder->reps[0] - 1 - mf->read_ahead]
              # We don't use read_ahead, so it's 0
              match_byte_pos = pos - @state.reps[0] - 1
              match_byte = @match_finder.buffer.getbyte(match_byte_pos) if match_byte_pos >= 0 && match_byte_pos < @match_finder.buffer.bytesize

              # If match_byte is nil (shouldn't happen in normal operation),
              # fall back to normal literal encoding
              if match_byte.nil?
                encode_normal_literal(literal_offset, symbol, encoder)
              else
                encode_matched_literal(literal_offset, match_byte, symbol,
                                       encoder)
              end
            else
              # Normal literal (8-bit tree)
              encode_normal_literal(literal_offset, symbol, encoder)
            end

            # Update prev_byte
            @prev_byte = symbol
          end

          # Encode normal match
          def encode_match(distance, length, encoder, pos, match_pos,
_input_data)
            pos_state = pos & ((1 << @pb) - 1)

            # Encode is_match bit (1 for match) - uses OLD state value
            prob_is_match = @models.is_match[@state.value][pos_state]
            encoder.queue_bit(prob_is_match, 1)

            # Encode is_rep bit (0 for normal match) - uses OLD state value
            prob_is_rep = @models.is_rep[@state.value]
            encoder.queue_bit(prob_is_rep, 0)

            # CRITICAL: Update state BEFORE encoding length/distance (XZ Utils order)
            # This also updates reps. Reps are stored 0-based (distance - 1),
            # matching XZ Utils and the decoder's rep0 convention.
            @state.update_match!(distance - 1)

            # Encode length - uses NEW state value
            encode_match_length(length, pos_state, encoder)

            # Encode distance - uses NEW state value
            encode_distance(distance, length, encoder)

            # Update prev_byte (last byte of match)
            # Read from match finder buffer: match_pos - distance + length - 1
            last_byte_pos = match_pos - distance + length - 1
            @prev_byte = @match_finder.buffer.getbyte(last_byte_pos) if last_byte_pos >= 0 && last_byte_pos < @match_finder.buffer.bytesize
          end

          # Encode repeated match (using rep0-rep3)
          # Ported from XZ Utils rep_match function
          def encode_repeated_match(rep, length, encoder, pos, match_pos)
            pos_state = pos & ((1 << @pb) - 1)

            # Encode is_match bit (1 for match) - uses OLD state value
            prob_is_match = @models.is_match[@state.value][pos_state]
            encoder.queue_bit(prob_is_match, 1)

            # Encode is_rep bit (1 for repeated match) - uses OLD state value
            prob_is_rep = @models.is_rep[@state.value]
            encoder.queue_bit(prob_is_rep, 1)

            prob_is_rep0 = @models.is_rep0[@state.value]
            if rep.zero?
              # rep0 (shortest distance)
              encoder.queue_bit(prob_is_rep0, 0)

              prob_is_rep0_long = @models.is_rep0_long[@state.value][pos_state]
              encoder.queue_bit(prob_is_rep0_long, length == 1 ? 0 : 1)
            else
              # rep1, rep2, or rep3
              encoder.queue_bit(prob_is_rep0, 1)

              prob_is_rep1 = @models.is_rep1[@state.value]
              if rep == 1
                # rep1
                encoder.queue_bit(prob_is_rep1, 0)
              else
                # rep2 or rep3
                encoder.queue_bit(prob_is_rep1, 1)

                prob_is_rep2 = @models.is_rep2[@state.value]
                encoder.queue_bit(prob_is_rep2, rep - 2)
              end

              # XZ Utils rep_match: capture the selected distance BEFORE
              # rotating, then shift reps down (lzma_encoder.c):
              #   distance = reps[rep];
              #   for (i = rep; i > 0; --i) reps[i] = reps[i-1];
              #   reps[0] = distance;
              distance = @state.reps[rep]
              rep.downto(1) { |i| @state.reps[i] = @state.reps[i - 1] }
              @state.reps[0] = distance
            end

            # Update state based on match length
            if length == 1
              @state.update_short_rep!
            else
              # Encode length using the REP length coder (rep matches have
              # their own length models, decoder's @rep_length_coder)
              encode_match_length(length, pos_state, encoder,
                                  @models.rep_len_encoder)
              @state.update_long_rep!
            end

            # Update prev_byte (last byte of the match region in the stream)
            last_byte_pos = match_pos + length - 1
            @prev_byte = @match_finder.buffer.getbyte(last_byte_pos) if last_byte_pos >= 0 && last_byte_pos < @match_finder.buffer.bytesize
          end

          # Get literal subcoder flat index
          # Ported from XZ Utils literal_subcoder macro in lzma_common.h:
          # #define literal_subcoder(probs, lc, literal_mask, pos, prev_byte) \
          #   ((probs) + UINT32_C(3) * \
          #     (((((pos) << 8) + (prev_byte)) & (literal_mask)) << (lc)))
          # where literal_mask = (0x100 << lp) - (0x100 >> lc)
          #
          # The factor of 3 gives each context a 0x300-sized subcoder and
          # MUST match the decoder's base_offset = 3 * (lit_state << lc).
          #
          # Returns the flat index into the literal probability array.
          def get_literal_state(pos, prev_byte)
            literal_mask = (0x100 << @lp) - (0x100 >> @lc)
            3 * ((((pos << 8) + prev_byte) & literal_mask) << @lc)
          end

          # Get byte from dictionary at distance back
          def get_dictionary_byte(distance)
            if distance.positive? &&
                distance <= @dictionary.buffer.bytesize
              @dictionary.get_byte(distance)
            end
          end

          # Encode normal literal (8-bit tree)
          # Ported from XZ Utils rc_bittree() for normal literals
          # @param literal_offset [Integer] Base offset into flat literal array
          # @param symbol [Integer] The literal byte to encode (0-255)
          # @param encoder [XZBufferedRangeEncoder] The range encoder
          def encode_normal_literal(literal_offset, symbol, encoder)
            context = 1
            8.downto(1) do |i|
              bit = (symbol >> (i - 1)) & 1
              encoder.queue_bit(@models.literal[literal_offset + context], bit)
              context = (context << 1) | bit
            end
          end

          # Encode matched literal (compare with match byte)
          # Ported from XZ Utils literal_matched() in lzma_encoder.c
          # @param literal_offset [Integer] Base offset into flat literal array
          # @param match_byte [Integer] The match byte to compare against
          # @param symbol [Integer] The literal byte to encode (0-255)
          # @param encoder [XZBufferedRangeEncoder] The range encoder
          def encode_matched_literal(literal_offset, match_byte, symbol,
encoder)
            offset = 0x100
            symbol += 0x100 # Start symbol at 256 (XZ Utils algorithm)

            # Loop until symbol reaches 0x10000 (65536)
            while symbol < 0x10000
              match_byte <<= 1
              match_bit = match_byte & offset
              subcoder_index = offset + match_bit + (symbol >> 8)
              bit = (symbol >> 7) & 1

              encoder.queue_bit(@models.literal[literal_offset + subcoder_index],
                                bit)

              symbol <<= 1
              offset &= ~(match_byte ^ symbol)
            end
          end

          # Encode match length
          # len_encoder is the length model set to use: match_len_encoder for
          # normal matches, rep_len_encoder for repeated matches.
          def encode_match_length(length, pos_state, encoder,
                                  len_encoder = @models.match_len_encoder)
            len = length - MATCH_LEN_MIN

            if len < LEN_LOW_SYMBOLS
              # Low: 0-7
              encoder.queue_bit(len_encoder.choice, 0)
              encode_bittree(
                len_encoder.low[pos_state],
                NUM_LEN_LOW_BITS,
                len,
                encoder,
              )
            elsif len < LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS
              # Mid: 8-15
              encoder.queue_bit(len_encoder.choice, 1)
              encoder.queue_bit(len_encoder.choice2, 0)
              encode_bittree(
                len_encoder.mid[pos_state],
                NUM_LEN_MID_BITS,
                len - LEN_LOW_SYMBOLS,
                encoder,
              )
            else
              # High: 16-271
              encoder.queue_bit(len_encoder.choice, 1)
              encoder.queue_bit(len_encoder.choice2, 1)
              high_len = len - LEN_LOW_SYMBOLS - LEN_MID_SYMBOLS
              encode_bittree(
                len_encoder.high,
                NUM_LEN_HIGH_BITS,
                high_len,
                encoder,
              )
            end
          end

          # Encode distance using slot encoding
          def encode_distance(distance, length, encoder)
            # get_dist_slot expects a 0-based distance (xz fastpos.h:
            # dist 4 -> slot 4, dist 5 -> slot 4). The decoder computes
            # rep0 = base + footer the same 0-based way.
            dist0 = distance - 1
            dist_slot = get_dist_slot(dist0)
            len_state = get_len_to_pos_state(length)

            # Encode distance slot
            # @dist_slot is organized as [len_to_pos_state][dist_slot]
            encode_bittree(
              @models.dist_slot[len_state],
              NUM_DIST_SLOT_BITS,
              dist_slot,
              encoder,
            )

            # Encode distance footer
            if dist_slot >= START_POS_MODEL_INDEX
              footer_bits = (dist_slot >> 1) - 1
              base = (2 | (dist_slot & 1)) << footer_bits
              dist_reduced = dist0 - base

              if dist_slot < END_POS_MODEL_INDEX
                # Use probability models
                # XZ Utils: rc_bittree_reverse(&coder->rc, coder->dist_special + base - dist_slot - 1, ...)
                encode_bittree_reverse(
                  @models.dist_special,
                  dist_reduced,
                  footer_bits,
                  base - dist_slot - 1,
                  encoder,
                )
              else
                # Direct bits + alignment
                direct_bits = footer_bits - DIST_ALIGN_BITS
                encoder.queue_direct_bits(
                  dist_reduced >> DIST_ALIGN_BITS,
                  direct_bits,
                )
                align_mask = (1 << DIST_ALIGN_BITS) - 1
                encode_bittree_reverse(
                  @models.dist_align,
                  dist_reduced & align_mask,
                  DIST_ALIGN_BITS,
                  0,
                  encoder,
                )
              end
            end
          end

          # Encode bittree (MSB first)
          def encode_bittree(probs, num_bits, value, encoder)
            context = 1
            num_bits.downto(1) do |i|
              bit = (value >> (i - 1)) & 1
              encoder.queue_bit(probs[context], bit)
              context = (context << 1) | bit
            end
          end

          # Encode bittree in reverse (LSB first)
          def encode_bittree_reverse(probs, value, num_bits, offset, encoder)
            context = 1
            num_bits.times do |i|
              bit = (value >> i) & 1
              encoder.queue_bit(probs[offset + context], bit)
              context = (context << 1) | bit
            end
          end

          # Get distance slot for distance
          def get_dist_slot(distance)
            if distance < NUM_FULL_DISTANCES
              distance < 4 ? distance : fast_pos_small(distance)
            else
              fast_pos_large(distance)
            end
          end

          # Fast position calculation for small distances
          def fast_pos_small(distance)
            slot = 0
            dist = distance
            while dist > 3
              dist >>= 1
              slot += 2
            end
            slot + dist
          end

          # Fast position calculation for large distances
          def fast_pos_large(distance)
            # Find highest bit position
            n = 31
            while n >= 0
              break if (distance >> n) != 0

              n -= 1
            end
            # slot = 2 * n + high_bit
            ((n << 1) + ((distance >> (n - 1)) & 1))
          end

          # Map length to position state
          def get_len_to_pos_state(length)
            len = length - MATCH_LEN_MIN
            len < NUM_LEN_TO_POS_STATES ? len : NUM_LEN_TO_POS_STATES - 1
          end

          # Encode dictionary size to LZMA2 property byte
          # @param dict_size [Integer] Dictionary size
          # @return [Integer] Property byte (0-40)
          def encode_dict_size(dict_size)
            # Clamp to valid range
            d = [dict_size, Omnizip::Algorithms::LZMA2Const::DICT_SIZE_MIN].max

            # Calculate log2 of dict_size
            log2_size = 0
            temp = d
            while temp > 1
              log2_size += 1
              temp >>= 1
            end

            # Encoding formula for power-of-2 sizes:
            # d = 2 * (log2_size - 12)
            if d == (1 << log2_size)
              # Exact power of 2
              [(log2_size - 12) * 2, 40].min
            else
              # Between 2^n and 2^n + 2^(n-1), use odd encoding
              [((log2_size - 12) * 2) + 1, 40].min
            end
          end
        end
      end
    end
  end
end

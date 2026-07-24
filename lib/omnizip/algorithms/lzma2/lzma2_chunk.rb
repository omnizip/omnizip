# frozen_string_literal: true

module Omnizip
  module Algorithms
    class LZMA2 < Algorithm
      # LZMA2 Chunk structure using Array#pack for binary serialization
      class LZMA2Chunk
        TYPE_END = :end
        TYPE_UNCOMPRESSED = :uncompressed
        TYPE_COMPRESSED = :compressed

        attr_reader :chunk_type, :uncompressed_data, :compressed_data,
                    :properties, :control_byte

        # Factory method for end marker
        def self.end_chunk
          new(
            chunk_type: TYPE_END,
            uncompressed_data: "",
            compressed_data: "",
            need_dict_reset: false,
            need_state_reset: false,
            need_props: false,
          )
        end

        def initialize(chunk_type:, need_dict_reset:, need_state_reset:,
                       need_props:, uncompressed_data: "",
                       compressed_data: "", properties: nil,
                       compressed_size: nil)
          # Validate chunk_type
          valid_types = [TYPE_END, TYPE_UNCOMPRESSED, TYPE_COMPRESSED]
          unless valid_types.include?(chunk_type)
            raise ArgumentError,
                  "Invalid chunk_type: #{chunk_type.inspect}. " \
                  "Must be :end, :uncompressed, or :compressed"
          end

          @chunk_type = chunk_type
          @uncompressed_data = uncompressed_data
          @compressed_data = compressed_data
          # For XZ format, compressed_size excludes flush bytes
          # For standalone LZMA2, compressed_size includes all bytes
          @compressed_size = compressed_size || @compressed_data.bytesize
          @properties = properties
          @need_dict_reset = need_dict_reset
          @need_state_reset = need_state_reset
          @need_props = need_props

          @control_byte = build_control_byte if chunk_type != TYPE_END
        end

        # Serialize to binary format
        def to_bytes
          case @chunk_type
          when TYPE_END
            [0x00].pack("C")
          when TYPE_UNCOMPRESSED
            serialize_uncompressed
          when TYPE_COMPRESSED
            serialize_compressed
          end
        end

        private

        def build_control_byte
          case @chunk_type
          when TYPE_COMPRESSED
            # XZ Utils LZMA2 compressed chunk format:
            # Base is 0x80 (bit 7 = 1 for compressed)
            # Bits 6-5 encode reset state (shifted left by 5):
            #   3 << 5 = 0x60 = dict reset + state reset + properties
            #   2 << 5 = 0x40 = state reset + properties
            #   1 << 5 = 0x20 = state reset only
            #   0 << 5 = 0x00 = no reset (no properties)
            #
            # Control byte format: 0x80 + (reset_type << 5)
            # High 5 bits of (uncompressed_size - 1) are added later in serialize_compressed

            control = if @need_props
                        if @need_dict_reset
                          0x80 + (3 << 5) # 0xE0 = dict reset + state reset + properties
                        elsif @need_state_reset
                          0x80 + (2 << 5) # 0xC0 = state reset + properties
                        else
                          # This shouldn't happen - if need_props, we need some reset
                          0x80 + (2 << 5) # Default to state reset + properties
                        end
                      elsif @need_state_reset
                        0x80 + (1 << 5)
                      else
                        0x80 # 0x80 = no reset
                      end

            # DEBUG: Print control byte calculation
            if ENV["DEBUG_CHUNK"]
              warn "LZMA2Chunk build_control_byte: need_props=#{@need_props}, need_dict_reset=#{@need_dict_reset}, need_state_reset=#{@need_state_reset}, control=0x#{control.to_s(16)}"
            end

            control
          when TYPE_UNCOMPRESSED
            # XZ Utils LZMA2 uncompressed chunk format:
            # Control byte is simply 1 or 2 (NOT complex bit encoding!)
            # 1 = dictionary reset
            # 2 = no dictionary reset
            if @need_dict_reset
              1
            else
              2
            end
          end
        end

        def serialize_uncompressed
          size = @uncompressed_data.bytesize - 1

          # LZMA2 uncompressed chunk format (matches XZ Utils lzma2_encoder.c lzma2_header_uncompressed):
          # 1 byte: control (1 = dict reset, 2 = no reset)
          # 2 bytes: Uncompressed Size Minus One in BIG-ENDIAN
          # N bytes: uncompressed data
          [
            @control_byte,              # Control byte (1 or 2)
            (size >> 8) & 0xFF,         # Size high byte (BIG-ENDIAN)
            size & 0xFF,                # Size low byte (BIG-ENDIAN)
          ].pack("CCC") + @uncompressed_data
        end

        def serialize_compressed
          uncomp_size = @uncompressed_data.bytesize - 1
          comp_size = @compressed_size - 1

          # Add high 5 bits to control byte
          high_bits = ((uncomp_size >> 16) & 0x1F)
          control = @control_byte | high_bits

          # DEBUG: Print final control byte calculation
          if ENV["DEBUG_CHUNK"]
            warn "LZMA2Chunk serialize_compressed: @control_byte=0x#{@control_byte.to_s(16)}, high_bits=0x#{high_bits.to_s(16)}, final_control=0x#{control.to_s(16)}"
            warn "  uncomp_size=#{@uncompressed_data.bytesize} (uncomp_size-1=#{uncomp_size}), comp_size=#{@compressed_size}"
          end

          # XZ Utils LZMA2 compressed chunk format (matches lzma2_encoder.c lzma2_header_lzma):
          # 1 byte: control + high 5 bits of (uncompressed_size - 1)
          # 2 bytes: low 16 bits of (uncompressed_size - 1) in BIG-ENDIAN
          # 2 bytes: (compressed_size - 1) in BIG-ENDIAN
          header = [
            control,
            (uncomp_size >> 8) & 0xFF, # Uncompressed size mid byte (BIG-ENDIAN)
            uncomp_size & 0xFF,          # Uncompressed size low byte (BIG-ENDIAN)
            (comp_size >> 8) & 0xFF,     # Compressed size high byte (BIG-ENDIAN)
            comp_size & 0xFF,            # Compressed size low byte (BIG-ENDIAN)
          ].pack("CCCCC")

          prop_bytes = @properties ? [@properties].pack("C") : ""
          header + prop_bytes + @compressed_data
        end
      end
    end
  end
end

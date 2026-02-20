# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Ole
      # OLE header parser
      #
      # Parses the 512-byte header block from OLE compound documents.
      # The first 76 bytes contain the header structure, followed by
      # up to 109 BAT block indices.
      class Header
        include Constants

        # Pack format for header structure
        PACK = "a8 a16 v2 a2 v2 a6 V3 a4 V5"

        # @return [String] 8-byte OLE magic signature
        attr_accessor :magic

        # @return [String] 16-byte CLSID (usually zeros)
        attr_accessor :clsid

        # @return [Integer] Minor version (usually 59)
        attr_accessor :minor_ver

        # @return [Integer] Major version (3 or 4)
        attr_accessor :major_ver

        # @return [String] 2-byte byte order marker
        attr_accessor :byte_order

        # @return [Integer] Big block shift (9 = 512 bytes)
        attr_accessor :b_shift

        # @return [Integer] Small block shift (6 = 64 bytes)
        attr_accessor :s_shift

        # @return [String] 6-byte reserved field
        attr_accessor :reserved

        # @return [Integer] Number of SECTs in directory (0 for v3)
        attr_accessor :csectdir

        # @return [Integer] Number of BAT blocks
        attr_accessor :num_bat

        # @return [Integer] First block of directory entries
        attr_accessor :dirent_start

        # @return [String] 4-byte transaction signature
        attr_accessor :transacting_signature

        # @return [Integer] Small block threshold (4096)
        attr_accessor :threshold

        # @return [Integer] First block of SBAT
        attr_accessor :sbat_start

        # @return [Integer] Number of SBAT blocks
        attr_accessor :num_sbat

        # @return [Integer] First block of Meta BAT
        attr_accessor :mbat_start

        # @return [Integer] Number of Meta BAT blocks
        attr_accessor :num_mbat

        # Parse header from binary data
        #
        # @param data [String] 512-byte header block
        # @return [Header] Parsed header object
        # @raise [ArgumentError] If data is invalid
        def self.parse(data)
          raise ArgumentError, "Header data too short" if data.nil? || data.bytesize < HEADER_SIZE

          header = new
          header.unpack(data)
          header.validate!
          header
        end

        # Create default header for new documents
        #
        # @return [Header] New header with default values
        def self.create
          header = new
          header.apply_defaults
          header
        end

        # Initialize header
        def initialize
          apply_defaults
        end

        # Apply default values
        def apply_defaults
          @magic = MAGIC.dup
          @clsid = "\x00".b * 16
          @minor_ver = 59
          @major_ver = 3
          @byte_order = BYTE_ORDER_LE.dup
          @b_shift = DEFAULT_BIG_BLOCK_SHIFT
          @s_shift = DEFAULT_SMALL_BLOCK_SHIFT
          @reserved = "\x00".b * 6
          @csectdir = 0
          @num_bat = 1
          @dirent_start = EOC
          @transacting_signature = "\x00".b * 4
          @threshold = DEFAULT_THRESHOLD
          @sbat_start = EOC
          @num_sbat = 0
          @mbat_start = EOC
          @num_mbat = 0
        end

        # Get big block size
        #
        # @return [Integer] Block size in bytes
        def big_block_size
          1 << @b_shift
        end

        # Get small block size
        #
        # @return [Integer] Block size in bytes
        def small_block_size
          1 << @s_shift
        end

        # Unpack header from binary data
        #
        # @param data [String] Binary data
        def unpack(data)
          values = data[0, HEADER_SIZE].unpack(PACK)
          @magic = values[0]
          @clsid = values[1]
          @minor_ver = values[2]
          @major_ver = values[3]
          @byte_order = values[4]
          @b_shift = values[5]
          @s_shift = values[6]
          @reserved = values[7]
          @csectdir = values[8]
          @num_bat = values[9]
          @dirent_start = values[10]
          @transacting_signature = values[11]
          @threshold = values[12]
          @sbat_start = values[13]
          @num_sbat = values[14]
          @mbat_start = values[15]
          @num_mbat = values[16]
        end

        # Pack header to binary data
        #
        # @return [String] 76-byte header binary data
        def pack
          [
            @magic, @clsid, @minor_ver, @major_ver, @byte_order,
            @b_shift, @s_shift, @reserved, @csectdir, @num_bat,
            @dirent_start, @transacting_signature, @threshold,
            @sbat_start, @num_sbat, @mbat_start, @num_mbat
          ].pack(PACK)
        end

        # Validate header structure
        #
        # @raise [ArgumentError] If header is invalid
        def validate!
          unless @magic == MAGIC
            raise ArgumentError, "Invalid OLE magic signature"
          end

          if @num_bat.zero?
            raise ArgumentError, "Invalid OLE: no BAT blocks"
          end

          if @s_shift > @b_shift || @b_shift <= 6 || @b_shift >= 31
            raise ArgumentError, "Invalid block shift values"
          end

          unless @byte_order == BYTE_ORDER_LE
            raise ArgumentError, "Only little-endian OLE files are supported"
          end

          if @threshold != DEFAULT_THRESHOLD
            # Warning, not error
          end

          true
        end
      end
    end
  end
end

# frozen_string_literal: true

module Omnizip
  module Formats
    module SevenZip
      # Constants for .7z archive format
      # Based on 7-Zip specification
      module Constants
        # Archive signature and header
        SIGNATURE = "7z\xBC\xAF\x27\x1C".b.freeze
        SIGNATURE_SIZE = 6
        START_HEADER_SIZE = 32 # 0x20
        MAJOR_VERSION = 0

        # Property IDs for .7z format structure
        module PropertyId
          K_END = 0x00
          HEADER = 0x01
          ARCHIVE_PROPERTIES = 0x02
          ADDITIONAL_STREAMS_INFO = 0x03
          MAIN_STREAMS_INFO = 0x04
          FILES_INFO = 0x05
          PACK_INFO = 0x06
          UNPACK_INFO = 0x07
          SUBSTREAMS_INFO = 0x08
          SIZE = 0x09
          CRC = 0x0A
          FOLDER = 0x0B
          CODERS_UNPACK_SIZE = 0x0C
          NUM_UNPACK_STREAM = 0x0D
          EMPTY_STREAM = 0x0E
          EMPTY_FILE = 0x0F
          ANTI = 0x10
          NAME = 0x11
          CTIME = 0x12
          ATIME = 0x13
          MTIME = 0x14
          WIN_ATTRIB = 0x15
          COMMENT = 0x16
          ENCODED_HEADER = 0x17
          START_POS = 0x18
          DUMMY = 0x19
        end

        # Method IDs for compression algorithms
        module MethodId
          # Compression methods
          COPY = 0x00
          LZMA = 0x030101
          LZMA2 = 0x21
          PPMD = 0x030401
          BZIP2 = 0x040202
          DEFLATE = 0x040108
          DEFLATE64 = 0x040109

          # Crypto methods
          AES = 0x06F10701

          def self.name(id)
            case id
            when COPY then "Copy"
            when LZMA then "LZMA"
            when LZMA2 then "LZMA2"
            when PPMD then "PPMd"
            when BZIP2 then "BZip2"
            when DEFLATE then "Deflate"
            when DEFLATE64 then "Deflate64"
            when AES then "AES256"
            else "Unknown(0x#{id.to_s(16)})"
            end
          end
        end

        # Filter IDs
        module FilterId
          # BCJ filters for executable files
          BCJ_X86 = 0x03030103
          BCJ_PPC = 0x03030205
          BCJ_IA64 = 0x03030401
          BCJ_ARM = 0x03030501
          BCJ_ARMT = 0x03030701
          BCJ_SPARC = 0x03030805

          # Delta filter
          DELTA = 0x03

          def self.name(id)
            case id
            when BCJ_X86 then "BCJ-x86"
            when BCJ_PPC then "BCJ-PPC"
            when BCJ_IA64 then "BCJ-IA64"
            when BCJ_ARM then "BCJ-ARM"
            when BCJ_ARMT then "BCJ-ARMT"
            when BCJ_SPARC then "BCJ-SPARC"
            when DELTA then "Delta"
            else "Unknown(0x#{id.to_s(16)})"
            end
          end
        end

        # Maximum limits
        MAX_NUM_CODERS = 4
        MAX_NUM_BONDS = 3
        MAX_NUM_PACK_STREAMS = 4
      end
    end
  end
end

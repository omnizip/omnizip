# frozen_string_literal: true

module Omnizip
  module Formats
    module Rpm
      # RPM format constants
      #
      # Defines magic numbers, header constants, and type definitions
      # for RPM package parsing.
      module Constants
        # RPM lead magic bytes
        LEAD_MAGIC = "\xed\xab\xee\xdb".b

        # RPM header magic bytes (8 bytes)
        HEADER_MAGIC = "\x8e\xad\xe8\x01\x00\x00\x00\x00".b

        # Lead structure size (96 bytes)
        LEAD_SIZE = 96

        # Header header size (16 bytes: magic + index_count + data_length)
        HEADER_HEADER_SIZE = 16

        # Tag entry size (16 bytes: tag + type + offset + count)
        TAG_ENTRY_SIZE = 16

        # Header signed type (signature present)
        HEADER_SIGNED_TYPE = 5

        # Package types
        PACKAGE_BINARY = 0
        PACKAGE_SOURCE = 1

        # Dependency flags
        FLAG_LESS = (1 << 1)
        FLAG_GREATER = (1 << 2)
        FLAG_EQUAL = (1 << 3)

        # File flags
        FILE_CONFIG = (1 << 0)
        FILE_DOC = (1 << 1)
        FILE_LICENSE = (1 << 3)
        FILE_README = (1 << 4)

        # Tag types
        TYPE_NULL = 0
        TYPE_CHAR = 1
        TYPE_INT8 = 2
        TYPE_INT16 = 3
        TYPE_INT32 = 4
        TYPE_INT64 = 5
        TYPE_STRING = 6
        TYPE_BINARY = 7
        TYPE_STRING_ARRAY = 8
        TYPE_I18NSTRING = 9
      end
    end
  end
end

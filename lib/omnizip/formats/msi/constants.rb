# frozen_string_literal: true

module Omnizip
  module Formats
    module Msi
      # MSI-specific constants
      #
      # MSI files use OLE compound document format with additional
      # semantic structures for database tables and embedded cabinets.
      module Constants
        # Column type codes used in _Columns table
        # Format: first char is type, rest is size/category

        # String types: s0-s255
        # String index into string pool, category indicates max length
        STRING_TYPE = "s"

        # Integer types
        INT16_TYPE = "i2" # 2-byte signed integer
        INT32_TYPE = "i4" # 4-byte signed integer

        # Binary/stream type
        BINARY_TYPE = "v0" # Binary data stored in separate stream

        # Object type (temporary)
        OBJECT_TYPE = "O0"

        # Special column category values
        CATEGORY_TEXT = 0
        CATEGORY_UPPERCASE = 1
        CATEGORY_LOWERCASE = 2
        CATEGORY_PATH = 3
        CATEGORY_FILENAME = 4
        CATEGORY_CONDITION = 5
        CATEGORY_GUID = 6
        CATEGORY_VERSION = 7
        CATEGORY_LANGUAGE = 8
        CATEGORY_BINARY = 9
        CATEGORY_TEMPLATE = 10
        CATEGORY_DOUBLE = 11
        CATEGORY_CABINET = 12
        CATEGORY_SHORTCUT = 13
        CATEGORY_DEFAULT = 14
        CATEGORY_IDENTIFIER = 15

        # Standard MSI table names
        TABLES_STREAM = "_Tables"
        COLUMNS_STREAM = "_Columns"
        STRING_POOL_STREAM = "_StringPool"
        STRING_DATA_STREAM = "_StringData"

        # Application tables
        FILE_TABLE = "File"
        COMPONENT_TABLE = "Component"
        DIRECTORY_TABLE = "Directory"
        MEDIA_TABLE = "Media"
        STREAMS_TABLE = "_Streams"

        # File attributes (File.Attributes column)
        FILE_ATTR_READONLY = 0x00000001
        FILE_ATTR_HIDDEN = 0x00000002
        FILE_ATTR_SYSTEM = 0x00000004
        FILE_ATTR_VITAL = 0x00000100
        FILE_ATTR_CHECKSUM = 0x00000400
        FILE_ATTR_PATCHADDED = 0x00001000
        FILE_ATTR_NONCOMPRESSED = 0x00002000
        FILE_ATTR_COMPRESSED = 0x00004000

        # Directory table special values
        TARGET_DIR = "TARGETDIR"
        SOURCE_DIR = "SourceDir"
        PROGRAM_FILES = "ProgramFilesFolder"
        PROGRAM_FILES_X64 = "ProgramFiles64Folder"
        WINDOWS_FOLDER = "WindowsFolder"
        SYSTEM_FOLDER = "SystemFolder"
        SYSTEM_X64_FOLDER = "System64Folder"

        # Component attributes
        COMP_ATTR_LOCAL_ONLY = 0x00000000
        COMP_ATTR_SOURCE_ONLY = 0x00000001
        COMP_ATTR_OPTIONAL = 0x00000002
        COMP_ATTR_REGISTRY_KEY_PATH = 0x00000004
        COMP_ATTR_SHARED_DLL = 0x00000008
        COMP_ATTR_PERMANENT = 0x00000010
        COMP_ATTR_ODBC = 0x00000020
        COMP_ATTR_TRANSITIVE = 0x00000040
        COMP_ATTR_NEVER_OVERWRITE = 0x00000080
        COMP_ATTR_64BIT = 0x00000100
        COMP_ATTR_DISABLE_REGISTRY = 0x00000200
        COMP_ATTR_UNINSTALL_ON_SUPERSEDE = 0x00000400
        COMP_ATTR_SHARED = 0x00000800

        # Media table cabinet name prefix
        # Cabinet names starting with # indicate embedded cabinets
        EMBEDDED_CAB_PREFIX = "#"

        # Decode MSI stream name from OLE storage
        #
        # MSI uses a custom encoding where characters in the range 0x3800-0x4800
        # are encoded using a MIME-like base64 scheme. Characters 0x4840 and 0x5
        # are prefix markers that should be skipped.
        #
        # Based on ReactOS/Wine's decode_streamname from msi/table.c
        #
        # @param encoded_name [String] Encoded stream name (UTF-16LE with special encoding)
        # @return [String] Decoded stream name
        def self.decode_stream_name(encoded_name)
          result = +""
          i = 0

          while i < encoded_name.length
            ch = encoded_name[i].ord

            if ch >= 0x3800 && ch < 0x4800
              # MIME-like encoding: two 6-bit values
              c = ch - 0x3800
              result << mime_char(c & 0x3f)
              result << mime_char((c >> 6) & 0x3f)
            elsif ch >= 0x4800 && ch < 0x4840
              # Single character encoding
              result << mime_char(ch - 0x4800)
            elsif i.zero? && [0x4840, 0x0005].include?(ch)
              # Prefix character to skip (0x4840 is always first for tables)
              # 0x5 is also a prefix seen in some streams
            else
              # Regular character (including ASCII)
              result << encoded_name[i]
            end

            i += 1
          end

          result
        end

        # Helper for MIME-like character encoding
        #
        # @param val [Integer] 6-bit value
        # @return [String] Encoded character
        def self.mime_char(val)
          if val < 10
            ("0".ord + val).chr
          elsif val < 36
            ("A".ord + val - 10).chr
          elsif val < 62
            ("a".ord + val - 36).chr
          elsif val == 62
            "."
          else
            "_"
          end
        end
        private_class_method :mime_char
      end
    end
  end
end

# frozen_string_literal: true

require "fileutils"
require "set"
require "tempfile"

module Omnizip
  module Formats
    module Msi
      # MSI String Pool
      #
      # Manages the interned string pool used by MSI files.
      # Strings are stored in _StringPool (UTF-16LE data with length prefix)
      # and _StringData (raw concatenated data).
      #
      # Based on Wine's msi_load_string_table implementation.
      class StringPool
        include Omnizip::Formats::Msi::Constants

        # @return [Ole::Storage] OLE storage reference
        attr_reader :ole

        # @return [Array<String>] Decoded strings indexed by pool position (1-based)
        attr_reader :strings

        # @return [Integer] Codepage for string encoding
        attr_reader :codepage

        # @return [Hash] Stream name map (decoded name => encoded name)
        attr_reader :stream_name_map

        # Initialize string pool from OLE storage
        #
        # @param ole [Ole::Storage] OLE storage object
        # @param stream_reader [Proc, Optional proc to read streams
        def initialize(ole, stream_reader = nil)
          @ole = ole
          @strings = [nil] # Index 0 is unused (1-based indexing)
          @codepage = 0
          @pool_cache = {}
          @stream_name_map = {}
          @stream_reader = stream_reader
          load
        end

        # Look up string by index
        #
        # @param index [Integer] String index (1-based)
        # @return [String, nil] Decoded string or nil if not found
        def [](index)
          return nil if index.nil? || index <= 0

          @strings[index]
        end

        # Get string count
        #
        # @return [Integer]
        def size
          @strings.size - 1 # Subtract 1 for nil at index 0
        end

        # Read stream from OLE, handling MSI stream name encoding
        #
        # @param base_name [String] Base stream name (e.g., "_StringPool")
        # @return [String, nil] Stream content or nil
        def read_stream(base_name)
          # Try various encodings of the stream name
          candidates = build_stream_name_candidates(base_name)

          candidates.each do |name|
            data = try_read_stream(name)
            return data if data && !data.empty?
          end

          nil
        end

        private

        # Build possible stream name variations
        #
        # @param base_name [String] Base stream name
        # @return [Array<String>] Possible stream names
        def build_stream_name_candidates(base_name)
          candidates = []

          # Try encoded name from the map first (set by Reader)
          stream_name_map = instance_variable_get(:@stream_name_map)
          if stream_name_map&.key?(base_name)
            candidates << stream_name_map[base_name]
          end

          # Try with standard prefix bytes
          # MSI uses \x01 prefix followed by UTF-16LE encoded name
          utf16le = base_name.encode("UTF-16LE")
          [1, 5].each do |prefix|
            candidates << prefix.chr.b.to_s.b << utf16le.b
          end

          # Try plain ASCII name
          candidates << base_name

          candidates.uniq
        end

        # Load string pool and string data from OLE streams
        def load
          # Use the provided stream reader if available, otherwise use our own
          reader = @stream_reader || method(:read_stream)

          # Read string pool - contains metadata about strings
          # Format: codepage (2 bytes) + reserved (2 bytes) + entries
          pool_data = reader.call(STRING_POOL_STREAM)
          return if pool_data.nil? || pool_data.empty?

          # Read string data - contains raw concatenated string data
          data = reader.call(STRING_DATA_STREAM)
          return if data.nil? || data.empty?

          # Parse pool header (first 2 bytes contain codepage info)
          @codepage = pool_data[0, 2].unpack1("v") if pool_data.bytesize >= 2

          # Parse string pool and data
          parse_pool_and_data(pool_data[4..], data)
        end

        # Attempt to read a stream
        #
        # @param name [String] Stream name
        # @return [String, nil] Stream content or nil
        def try_read_stream(name)
          @ole.read(name)
        rescue StandardError
          nil
        end

        # Parse string pool and data streams
        #
        # _StringPool format:
        # - Header: codepage (2 bytes) + reserved (2 bytes)
        # - Entries: (2-byte length + 2-byte ref_count) for each string
        #
        # _StringData format:
        # - Raw concatenated string data
        #
        # @param pool [String] Pool data (after header)
        # @param data [String] String data stream
        def parse_pool_and_data(pool, data)
          return if pool.nil? || pool.empty? || data.nil? || data.empty?

          # Calculate number of entries (each entry is 4 bytes: 2 for length + 2 for refs)
          num_entries = pool.bytesize / 4

          # Read entry metadata from pool
          entries = []
          num_entries.times do |i|
            offset = i * 4
            length = pool[offset, 2].unpack1("v")
            ref_count = pool[offset + 2, 2].unpack1("v")
            entries << { length: length, ref_count: ref_count }
          end

          # Read strings from data stream
          data_offset = 0
          entries.each do |entry|
            length = entry[:length]
            if length.positive? && data_offset + length <= data.bytesize
              str_data = data[data_offset, length]
              @strings << decode_string(str_data)
              data_offset += length
            else
              @strings << ""
            end
          end
        end

        # Decode string from string data stream
        #
        # Strings are stored in the MSI's codepage (typically Windows-1252).
        #
        # @param data [String] Raw string bytes
        # @return [String] Decoded UTF-8 string
        def decode_string(data)
          return "" if data.nil? || data.empty?

          # Try codepage encoding if set
          if @codepage.positive? && @codepage != 65001 # 65001 is UTF-8
            begin
              # Map common MSI codepages to Ruby encodings
              encoding = codepage_to_encoding(@codepage)
              return data.force_encoding(encoding).encode("UTF-8",
                                                          invalid: :replace, undef: :replace)
            rescue StandardError
              # Fall through
            end
          end

          # Try UTF-8 first (common for newer MSIs)
          begin
            if data.valid_encoding?
              return data.encode("UTF-8", invalid: :replace,
                                          undef: :replace)
            end
          rescue StandardError
            # Fall through
          end

          # Try Windows-1252 (most common MSI codepage)
          begin
            return data.force_encoding("Windows-1252").encode("UTF-8",
                                                              invalid: :replace, undef: :replace)
          rescue StandardError
            # Fall through
          end

          # Fallback to binary
          data.force_encoding("BINARY")
        end

        # Map Windows codepage to Ruby encoding name
        #
        # @param codepage [Integer] Windows codepage number
        # @return [String, nil] Ruby encoding name
        def codepage_to_encoding(codepage)
          case codepage
          when 1252, 0 then "Windows-1252"
          when 1250 then "Windows-1250"
          when 1251 then "Windows-1251"
          when 1253 then "Windows-1253"
          when 1254 then "Windows-1254"
          when 1255 then "Windows-1255"
          when 1256 then "Windows-1256"
          when 1257 then "Windows-1257"
          when 1258 then "Windows-1258"
          when 932 then "Windows-31J"
          when 936 then "GB2312"
          when 949 then "EUC-KR"
          when 950 then "Big5"
          when 65001 then "UTF-8"
          else "Windows-1252"
          end
        end
      end
    end
  end
end

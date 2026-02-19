# frozen_string_literal: true

module Omnizip
  module Formats
    module Iso
      # ISO 9660 Path Table
      # Provides efficient directory hierarchy lookup
      class PathTable
        attr_reader :entries

        # Path table entry
        class Entry
          attr_reader :name, :location, :parent_directory_number

          # Initialize entry
          #
          # @param name [String] Directory name
          # @param location [Integer] LBA location
          # @param parent_directory_number [Integer] Parent directory index
          def initialize(name, location, parent_directory_number)
            @name = name
            @location = location
            @parent_directory_number = parent_directory_number
          end

          # Get full path by traversing parent entries
          #
          # @param entries [Array<Entry>] All path table entries
          # @return [String] Full path
          def full_path(entries)
            return "/" if @parent_directory_number == 1 # Root

            parts = [@name]
            current_parent = @parent_directory_number

            while current_parent > 1
              parent = entries[current_parent - 1]
              break unless parent

              parts.unshift(parent.name)
              current_parent = parent.parent_directory_number
            end

            "/#{parts.join('/')}"
          end
        end

        # Initialize path table
        def initialize
          @entries = []
        end

        # Parse path table from binary data
        #
        # @param data [String] Binary path table data
        # @param size [Integer] Size of path table in bytes
        # @return [PathTable] Parsed path table
        def self.parse(data, size)
          new.tap { |pt| pt.parse(data, size) }
        end

        # Parse path table data
        #
        # @param data [String] Binary data
        # @param size [Integer] Size in bytes
        def parse(data, size)
          offset = 0

          while offset < size
            # Byte 0: Length of directory identifier
            name_length = data.getbyte(offset)
            break if name_length.zero?

            # Byte 1: Extended attribute record length
            data.getbyte(offset + 1)

            # Bytes 2-5: Location of extent (little-endian)
            location = data[offset + 2, 4].unpack1("V")

            # Bytes 6-7: Parent directory number
            parent = data[offset + 6, 2].unpack1("v")

            # Bytes 8+: Directory identifier
            name = data[offset + 8, name_length].strip

            # Handle root directory (zero-length name)
            name = "/" if name.empty?

            # Create entry
            @entries << Entry.new(name, location, parent)

            # Move to next entry
            # Length is 8 + name_length, padded to even boundary
            record_length = 8 + name_length
            record_length += 1 if record_length.odd?
            offset += record_length
          end
        end

        # Find entry by directory name
        #
        # @param name [String] Directory name
        # @return [Entry, nil] Found entry or nil
        def find_by_name(name)
          @entries.find { |e| e.name == name }
        end

        # Find entry by location
        #
        # @param location [Integer] LBA location
        # @return [Entry, nil] Found entry or nil
        def find_by_location(location)
          @entries.find { |e| e.location == location }
        end

        # Get root directory entry
        #
        # @return [Entry] Root entry
        def root
          @entries.first
        end
      end
    end
  end
end

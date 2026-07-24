# frozen_string_literal: true

module Omnizip
  module Formats
    module Msi
      # MSI File Entry
      #
      # Represents a single file within an MSI package.
      # File information is assembled from File, Component, and Directory tables.
      class Entry
        include Omnizip::Formats::Msi::Constants

        # @return [String] Full installation path
        attr_accessor :path

        # @return [String] File key (primary key from File table)
        attr_accessor :file_key

        # @return [String] Component key
        attr_accessor :component

        # @return [String] Filename from File table (may be "short|long" format)
        attr_accessor :filename

        # @return [String] Long filename (extracted from filename)
        attr_accessor :long_name

        # @return [String] Short filename (8.3 format)
        attr_accessor :short_name

        # @return [Integer] File size in bytes
        attr_accessor :size

        # @return [Integer] Sequence number (maps to Media table)
        attr_accessor :sequence

        # @return [String] File version
        attr_accessor :version

        # @return [String] File language
        attr_accessor :language

        # @return [Integer] File attributes
        attr_accessor :attributes

        # @return [Time, nil] Creation time (from CAB)
        attr_accessor :creation_time

        # @return [Time, nil] Last write time (from CAB)
        attr_accessor :last_write_time

        # Check if entry is a directory
        #
        # @return [Boolean]
        def directory?
          false
        end

        # Check if entry is a file
        #
        # @return [Boolean]
        def file?
          true
        end

        # Check if file is compressed
        #
        # @return [Boolean]
        def compressed?
          @attributes&.anybits?(FILE_ATTR_COMPRESSED)
        end

        # Check if file is vital (must be present for installation)
        #
        # @return [Boolean]
        def vital?
          @attributes&.anybits?(FILE_ATTR_VITAL)
        end

        # Get file attributes as string
        #
        # @return [String] Attributes string (e.g., "Archive")
        def attributes_string
          attrs = []
          attrs << "Archive"
          attrs << "ReadOnly" if @attributes&.anybits?(FILE_ATTR_READONLY)
          attrs << "Hidden" if @attributes&.anybits?(FILE_ATTR_HIDDEN)
          attrs << "System" if @attributes&.anybits?(FILE_ATTR_SYSTEM)
          attrs.join(", ")
        end

        # Parse filename field
        #
        # MSI File.Filename can be:
        # - "short|long" - both short and long names
        # - "name" - just the name
        #
        # @param filename [String] Raw filename from File table
        def parse_filename(filename)
          @filename = filename

          if filename&.include?("|")
            parts = filename.split("|", 2)
            @short_name = parts[0]
            @long_name = parts[1]
          else
            @long_name = filename
            @short_name = nil
          end
        end

        # Get display filename (prefers long name)
        #
        # @return [String]
        def display_name
          @long_name || @short_name || @filename || ""
        end

        # Get path for display (Windows-style backslashes)
        #
        # @return [String]
        def windows_path
          @path&.gsub("/", "\\")
        end
      end
    end
  end
end

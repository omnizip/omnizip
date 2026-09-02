# frozen_string_literal: true

module Omnizip
  module Formats
    module Tar
      # TAR header parser (POSIX ustar format)
      #
      # Handles reading and writing 512-byte TAR headers
      class Header
        include Omnizip::Formats::Tar::Constants

        # Parse a TAR header from binary data
        #
        # @param header_data [String] 512 bytes of header data
        # @return [Entry, nil] Parsed entry or nil if end of archive
        def self.parse(header_data)
          return nil if header_data.nil? || header_data.bytesize < HEADER_SIZE
          return nil if all_zeros?(header_data)

          entry = Entry.new("")

          # Extract fields from header
          entry.name = extract_string(header_data, NAME_OFFSET, NAME_SIZE)
          entry.mode = extract_octal(header_data, MODE_OFFSET, MODE_SIZE)
          entry.uid = extract_octal(header_data, UID_OFFSET, UID_SIZE)
          entry.gid = extract_octal(header_data, GID_OFFSET, GID_SIZE)
          entry.size = extract_octal(header_data, SIZE_OFFSET, SIZE_SIZE)
          entry.mtime = Time.at(
            extract_octal(header_data, MTIME_OFFSET, MTIME_SIZE),
          )
          entry.typeflag = header_data[TYPEFLAG_OFFSET]
          entry.linkname = extract_string(
            header_data, LINKNAME_OFFSET, LINKNAME_SIZE
          )

          # Check for ustar format
          magic = extract_string(header_data, MAGIC_OFFSET, MAGIC_SIZE)
          if magic == USTAR_MAGIC
            entry.uname = extract_string(header_data, UNAME_OFFSET, UNAME_SIZE)
            entry.gname = extract_string(header_data, GNAME_OFFSET, GNAME_SIZE)
            entry.devmajor = extract_octal(
              header_data, DEVMAJOR_OFFSET, DEVMAJOR_SIZE
            )
            entry.devminor = extract_octal(
              header_data, DEVMINOR_OFFSET, DEVMINOR_SIZE
            )
            entry.prefix = extract_string(
              header_data, PREFIX_OFFSET, PREFIX_SIZE
            )
            # ustar stores long paths split across prefix + name;
            # consumers see the joined path
            unless entry.prefix.empty?
              entry.name = "#{entry.prefix}/#{entry.name}"
            end
          end

          # Verify checksum
          checksum = extract_octal(
            header_data, CHECKSUM_OFFSET, CHECKSUM_SIZE
          )
          calculated = Entry.calculate_checksum(header_data)
          unless checksum == calculated
            raise Error, "TAR header checksum mismatch"
          end

          entry
        end

        # Build a TAR header from an entry
        #
        # @param entry [Entry] Entry to build header for
        # @return [String] 512 bytes of header data
        def self.build(entry)
          header = "\0" * HEADER_SIZE

          # Write fields to header
          name, prefix = split_long_name(entry.name, entry.prefix)
          write_string(header, name, NAME_OFFSET, NAME_SIZE)
          write_octal(header, entry.mode, MODE_OFFSET, MODE_SIZE)
          write_octal(header, entry.uid, UID_OFFSET, UID_SIZE)
          write_octal(header, entry.gid, GID_OFFSET, GID_SIZE)
          write_octal(header, entry.size, SIZE_OFFSET, SIZE_SIZE)
          write_octal(
            header, entry.mtime.to_i, MTIME_OFFSET, MTIME_SIZE
          )
          header[TYPEFLAG_OFFSET] = entry.typeflag || TYPE_REGULAR
          write_string(header, entry.linkname, LINKNAME_OFFSET, LINKNAME_SIZE)

          # Write ustar magic and version
          write_string(header, USTAR_MAGIC, MAGIC_OFFSET, MAGIC_SIZE)
          write_string(header, USTAR_VERSION, VERSION_OFFSET, VERSION_SIZE)
          write_string(header, entry.uname, UNAME_OFFSET, UNAME_SIZE)
          write_string(header, entry.gname, GNAME_OFFSET, GNAME_SIZE)
          write_octal(header, entry.devmajor, DEVMAJOR_OFFSET, DEVMAJOR_SIZE)
          write_octal(header, entry.devminor, DEVMINOR_OFFSET, DEVMINOR_SIZE)
          write_string(header, prefix, PREFIX_OFFSET, PREFIX_SIZE)

          # Calculate and write checksum
          checksum = Entry.calculate_checksum(header)
          write_octal(header, checksum, CHECKSUM_OFFSET, CHECKSUM_SIZE)

          header
        end

        # Check if header data is all zeros (end of archive marker)
        #
        # @param data [String] Header data
        # @return [Boolean] true if all zeros
        def self.all_zeros?(data)
          data.bytes.all?(&:zero?)
        end

        # Extract a null-terminated string from header
        #
        # @param header [String] Header data
        # @param offset [Integer] Field offset
        # @param size [Integer] Field size
        # @return [String] Extracted string
        def self.extract_string(header, offset, size)
          field = header[offset, size]
          return "" if field.nil?

          # Find null terminator
          null_pos = field.index("\0")
          null_pos ? field[0...null_pos] : field
        end

        # Extract an octal number from header
        #
        # @param header [String] Header data
        # @param offset [Integer] Field offset
        # @param size [Integer] Field size
        # @return [Integer] Extracted number
        def self.extract_octal(header, offset, size)
          field = extract_string(header, offset, size)
          field.strip.to_i(8)
        end

        # Split a path for the ustar name (100) + prefix (155)
        # fields. Paths under 100 bytes pass through; longer paths
        # split at a "/" boundary, preferring the longest prefix
        # that keeps both halves in bounds. Raises when no ustar
        # representation exists — silent truncation corrupts
        # archives.
        #
        # @param path [String] Full entry path
        # @param prefix [String] Explicit prefix (wins when given)
        # @return [Array<String>] [name, prefix] pair
        def self.split_long_name(path, prefix = nil)
          path = path.to_s
          prefix = prefix.to_s
          return [path, prefix] if !prefix.empty? || path.bytesize < NAME_SIZE

          best = nil
          offset = -1
          while (slash = path.index("/", offset + 1))
            candidate_prefix = path[0...slash]
            candidate_name = path[(slash + 1)..]
            offset = slash

            next if candidate_prefix.bytesize >= PREFIX_SIZE
            next if candidate_name.bytesize >= NAME_SIZE

            best = [candidate_name, candidate_prefix]
          end

          return best if best

          raise Omnizip::FormatError,
                "Path too long for the ustar name+prefix fields " \
                "(no PAX/GNU long-name support): #{path}"
        end

        # Write a string to header
        #
        # @param header [String] Header data
        # @param value [String] Value to write
        # @param offset [Integer] Field offset
        # @param size [Integer] Field size
        def self.write_string(header, value, offset, size)
          value = value.to_s
          # Truncate if too long
          value = value[0, size - 1] if value.bytesize >= size
          header[offset, value.bytesize] = value
        end

        # Write an octal number to header
        #
        # @param header [String] Header data
        # @param value [Integer] Value to write
        # @param offset [Integer] Field offset
        # @param size [Integer] Field size
        def self.write_octal(header, value, offset, size)
          # Format as octal with leading zeros
          octal_str = format("%0#{size - 1}o", value.to_i)
          # Truncate if too long
          octal_str = octal_str[(-size + 1)..] if octal_str.bytesize >= size
          header[offset, octal_str.bytesize] = octal_str
        end

        private_class_method :extract_string, :extract_octal
        private_class_method :write_string, :write_octal, :all_zeros?
      end
    end
  end
end

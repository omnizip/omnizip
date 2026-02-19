# frozen_string_literal: true

require_relative "constants"
require_relative "../../checksums/crc32"

module Omnizip
  module Formats
    module SevenZip
      # Writes .7z archive header with metadata
      # Handles variable-length encoding and property sequences
      class HeaderWriter
        include Constants

        attr_reader :buffer

        # Initialize writer
        def initialize
          @buffer = String.new(encoding: "BINARY")
        end

        # Write archive signature and header
        #
        # @param next_header_data [String] Encoded next header
        # @param next_header_offset [Integer] Offset to next header
        # @return [String] Complete archive header
        def write_start_header(next_header_data, next_header_offset)
          header = String.new(encoding: "BINARY")

          # Signature (6 bytes)
          header << SIGNATURE

          # Version (2 bytes)
          header << [MAJOR_VERSION, MINOR_VERSION].pack("CC")

          # Calculate CRC for next header info
          next_header_info = String.new(encoding: "BINARY")
          next_header_info << [next_header_offset].pack("Q<")
          next_header_info << [next_header_data.bytesize].pack("Q<")

          crc = Omnizip::Checksums::Crc32.new
          crc.update(next_header_data)
          next_header_crc = crc.value

          next_header_info << [next_header_crc].pack("V")

          # Calculate CRC for next header info
          info_crc = Omnizip::Checksums::Crc32.new
          info_crc.update(next_header_info)

          # Start header CRC (4 bytes)
          header << [info_crc.value].pack("V")

          # Next header info (20 bytes)
          header << next_header_info

          header
        end

        # Encode variable-length number (7-Zip format)
        #
        # @param value [Integer] Number to encode
        # @return [String] Encoded bytes
        def write_number(value)
          return [value].pack("C") if value < 0x80

          # Determine how many bytes needed and encode accordingly
          if value < 0x4000 # 14-bit: 2 bytes
            first_byte = 0x80 | (value >> 8)
            second_byte = value & 0xFF
            [first_byte, second_byte].pack("C*")
          elsif value < 0x200000 # 21-bit: 3 bytes
            first_byte = 0xC0 | (value >> 16)
            second_byte = (value >> 8) & 0xFF
            third_byte = value & 0xFF
            [first_byte, second_byte, third_byte].pack("C*")
          elsif value < 0x10000000 # 28-bit: 4 bytes
            first_byte = 0xE0 | (value >> 24)
            [
              first_byte,
              (value >> 16) & 0xFF,
              (value >> 8) & 0xFF,
              value & 0xFF,
            ].pack("C*")
          elsif value < 0x800000000 # 35-bit: 5 bytes
            first_byte = 0xF0 | (value >> 32)
            [
              first_byte,
              (value >> 24) & 0xFF,
              (value >> 16) & 0xFF,
              (value >> 8) & 0xFF,
              value & 0xFF,
            ].pack("C*")
          elsif value < 0x40000000000 # 42-bit: 6 bytes
            first_byte = 0xF8 | (value >> 40)
            [
              first_byte,
              (value >> 32) & 0xFF,
              (value >> 24) & 0xFF,
              (value >> 16) & 0xFF,
              (value >> 8) & 0xFF,
              value & 0xFF,
            ].pack("C*")
          elsif value < 0x2000000000000 # 49-bit: 7 bytes
            first_byte = 0xFC | (value >> 48)
            [
              first_byte,
              (value >> 40) & 0xFF,
              (value >> 32) & 0xFF,
              (value >> 24) & 0xFF,
              (value >> 16) & 0xFF,
              (value >> 8) & 0xFF,
              value & 0xFF,
            ].pack("C*")
          else # 56-bit: 8 bytes
            first_byte = 0xFE | (value >> 56)
            [
              first_byte,
              (value >> 48) & 0xFF,
              (value >> 40) & 0xFF,
              (value >> 32) & 0xFF,
              (value >> 24) & 0xFF,
              (value >> 16) & 0xFF,
              (value >> 8) & 0xFF,
              value & 0xFF,
            ].pack("C*")
          end
        end

        # Write bit vector
        #
        # @param bits [Array<Boolean>] Bit values
        # @return [String] Encoded bit vector
        def write_bit_vector(bits)
          return [1].pack("C") if bits.all?

          data = [0].pack("C") # Not all defined
          num_bytes = (bits.size + 7) / 8

          bytes = Array.new(num_bytes, 0)
          bits.each_with_index do |bit, i|
            byte_idx = i / 8
            bit_idx = 7 - (i % 8)
            bytes[byte_idx] |= (1 << bit_idx) if bit
          end

          data << bytes.pack("C*")
          data
        end

        # Write pack info section
        #
        # @param pack_pos [Integer] Pack position
        # @param pack_sizes [Array<Integer>] Pack sizes
        # @param pack_crcs [Array<Integer, nil>] Pack CRCs (optional)
        # @return [String] Encoded pack info
        def write_pack_info(pack_pos, pack_sizes, pack_crcs = [])
          data = String.new(encoding: "BINARY")

          data << [PropertyId::PACK_INFO].pack("C")
          data << write_number(pack_pos)
          data << write_number(pack_sizes.size)

          # Sizes
          data << [PropertyId::SIZE].pack("C")
          pack_sizes.each do |size|
            data << write_number(size)
          end

          # CRCs (optional)
          unless pack_crcs.empty?
            data << [PropertyId::CRC].pack("C")
            defined_bits = pack_crcs.map { |crc| !crc.nil? }
            data << write_bit_vector(defined_bits)
            pack_crcs.each do |crc|
              data << [crc].pack("V") if crc
            end
          end

          data << [PropertyId::K_END].pack("C")
          data
        end

        # Write coder info
        #
        # @param method_id [Integer] Compression method ID
        # @param properties [String, nil] Coder properties
        # @return [String] Encoded coder
        def write_coder(method_id, properties = nil)
          data = String.new(encoding: "BINARY")

          # Determine ID size
          id_bytes = []
          temp_id = method_id
          while temp_id.positive?
            id_bytes.unshift(temp_id & 0xFF)
            temp_id >>= 8
          end
          id_bytes = [0] if id_bytes.empty?

          # Main byte
          main_byte = id_bytes.size
          main_byte |= 0x20 if properties # Has properties

          data << [main_byte].pack("C")
          data << id_bytes.pack("C*")

          # Properties
          if properties
            data << write_number(properties.bytesize)
            data << properties
          end

          data
        end

        # Write folder definition
        #
        # @param method_id [Integer] Compression method
        # @param properties [String, nil] Properties
        # @return [String] Encoded folder data
        def write_folder(method_id, properties)
          data = String.new(encoding: "BINARY")

          # Number of coders
          data << write_number(1)

          # Coder info
          data << write_coder(method_id, properties)

          # For simple case: no bind pairs needed
          # (single coder with single in/out stream)

          data
        end

        # Write folders section
        #
        # @param folders [Array<Hash>] Folder specs
        # @return [String] Encoded folders
        def write_folders(folders)
          data = String.new(encoding: "BINARY")
          data << [PropertyId::FOLDER].pack("C")
          data << write_number(folders.size)

          # Write external flag (0 = inline folders, 1 = external)
          data << [0].pack("C")

          folders.each do |folder|
            data << write_folder(
              folder[:method_id],
              folder[:properties],
            )
          end

          data
        end

        # Write unpack info section
        #
        # @param folders [Array<Hash>] Folder information
        # @return [String] Encoded unpack info
        def write_unpack_info(folders)
          data = String.new(encoding: "BINARY")

          data << [PropertyId::UNPACK_INFO].pack("C")
          data << write_folders(folders)

          # Coders unpack size
          data << [PropertyId::CODERS_UNPACK_SIZE].pack("C")
          folders.each do |folder|
            data << write_number(folder[:unpack_size])
          end

          data << [PropertyId::K_END].pack("C")
          data
        end

        # Write file names
        #
        # @param names [Array<String>] File names
        # @return [String] Encoded names
        def write_names(names)
          data = String.new(encoding: "BINARY")

          # Encode names as UTF-16LE
          names_data = String.new(encoding: "BINARY")
          names.each do |name|
            name.encode("UTF-16LE").each_byte do |byte|
              names_data << [byte].pack("C")
            end
            names_data << [0, 0].pack("CC") # Null terminator
          end

          data << write_number(names_data.bytesize + 1)
          data << [0].pack("C") # Not external
          data << names_data

          data
        end

        # Write timestamps
        #
        # @param prop_id [Integer] Property ID
        # @param times [Array<Time, nil>] Timestamps
        # @return [String] Encoded timestamps
        def write_timestamps(_prop_id, times)
          data = String.new(encoding: "BINARY")

          defined_bits = times.map { |t| !t.nil? }
          times_data = String.new(encoding: "BINARY")
          times_data << write_bit_vector(defined_bits)
          times_data << [0].pack("C") # Not external

          times.each do |time|
            next unless time

            # Convert to Windows FILETIME
            unix_time = time.to_i
            windows_time = (unix_time + 11_644_473_600) * 10_000_000
            times_data << [windows_time].pack("Q<")
          end

          data << write_number(times_data.bytesize)
          data << times_data
          data
        end

        # Write files info section
        #
        # @param entries [Array<Models::FileEntry>] File entries
        # @return [String] Encoded files info
        def write_files_info(entries)
          data = String.new(encoding: "BINARY")

          data << [PropertyId::FILES_INFO].pack("C")
          data << write_number(entries.size)

          # Names
          data << [PropertyId::NAME].pack("C")
          data << write_names(entries.map(&:name))

          # Empty stream flags
          empty_bits = entries.map { |e| !e.has_stream }
          if empty_bits.any?
            data << [PropertyId::EMPTY_STREAM].pack("C")
            empty_data = write_bit_vector(empty_bits)
            data << write_number(empty_data.bytesize)
            data << empty_data
          end

          # Modification times
          mtimes = entries.map(&:mtime)
          if mtimes.any?
            data << [PropertyId::MTIME].pack("C")
            data << write_timestamps(PropertyId::MTIME, mtimes)
          end

          # Attributes
          attrs = entries.map(&:attributes)
          if attrs.any?
            data << [PropertyId::WIN_ATTRIB].pack("C")
            defined_bits = attrs.map { |a| !a.nil? }
            attrs_data = String.new(encoding: "BINARY")
            attrs_data << write_bit_vector(defined_bits)
            attrs_data << [0].pack("C") # Not external
            attrs.each do |attr|
              attrs_data << [attr].pack("V") if attr
            end
            data << write_number(attrs_data.bytesize)
            data << attrs_data
          end

          data << [PropertyId::K_END].pack("C")
          data
        end

        # Write main streams info
        #
        # @param options [Hash] Stream information
        # @return [String] Encoded streams info
        def write_streams_info(options)
          data = String.new(encoding: "BINARY")

          data << [PropertyId::MAIN_STREAMS_INFO].pack("C")
          data << write_pack_info(
            options[:pack_pos],
            options[:pack_sizes],
            options[:pack_crcs],
          )
          data << write_unpack_info(options[:folders])

          # Substreams info - needed for solid archives with multiple files
          if options[:digests] && !options[:digests].empty?
            data << write_substreams_info(
              options[:unpack_sizes] || [],
              options[:digests],
              options[:folders],
            )
          end

          data << [PropertyId::K_END].pack("C")
          data
        end

        # Write substreams info section
        #
        # @param unpack_sizes [Array<Integer>] Unpack sizes per file
        # @param digests [Array<Integer>] CRC per file
        # @param folders [Array<Hash>] Folder information
        # @return [String] Encoded substreams info
        def write_substreams_info(unpack_sizes, digests, folders)
          data = String.new(encoding: "BINARY")

          data << [PropertyId::SUBSTREAMS_INFO].pack("C")

          # Write NUM_UNPACK_STREAM if multiple files in folder
          if digests.size > folders.size
            data << [PropertyId::NUM_UNPACK_STREAM].pack("C")
            folders.each do |_folder|
              # For solid archives, all files are in one folder
              data << write_number(digests.size)
            end
          end

          # Write unpack sizes if we have them and multiple files
          if unpack_sizes.size > 1
            data << [PropertyId::SIZE].pack("C")
            # Write all but last size (last is calculated from folder unpack size)
            unpack_sizes[0...-1].each do |size|
              data << write_number(size)
            end
          end

          # Write CRCs
          if digests && !digests.empty?
            data << [PropertyId::CRC].pack("C")
            defined_bits = digests.map { |d| !d.nil? }
            data << write_bit_vector(defined_bits)
            digests.each do |crc|
              data << [crc].pack("V") if crc
            end
          end

          data << [PropertyId::K_END].pack("C")
          data
        end

        # Write complete next header
        #
        # @param options [Hash] All header information
        # @return [String] Encoded next header
        def write_next_header(options)
          data = String.new(encoding: "BINARY")

          data << [PropertyId::HEADER].pack("C")
          data << write_streams_info(options[:streams]) if
            options[:streams]
          data << write_files_info(options[:entries]) if options[:entries]
          data << [PropertyId::K_END].pack("C")

          data
        end
      end
    end
  end
end

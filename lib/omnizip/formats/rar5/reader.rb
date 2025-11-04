# frozen_string_literal: true

require "lutaml/model"
require_relative "../rar/rar_format_base"
require_relative "decompressor"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 archive reader
      #
      # Reads RAR 5.x format archives, parsing headers and extracting file data
      # according to the RAR v5 specification.
      #
      # RAR 5 uses variable-length integers (vint) and improved header structure.
      #
      # @example Reading a RAR5 archive
      #   reader = Rar5::Reader.new
      #   File.open("archive.rar", "rb") do |file|
      #     entries = reader.read_archive(file)
      #     entries.each { |entry| puts entry.name }
      #   end
      class Reader < Rar::RarFormatBase
        # Initialize a RAR v5 reader
        def initialize
          super("rar5")
        end

        # Read a RAR v5 archive
        #
        # @param io [IO] The input stream
        # @return [Array<Entry>] The archive entries
        # @raise [FormatError] If the archive format is invalid
        def read_archive(io)
          unless verify_magic_bytes(io)
            raise FormatError, "Invalid RAR v5 signature"
          end

          entries = []

          # Read main header
          main_header = read_header(io)
          unless main_header.type == block_type_code(:main_header)
            raise FormatError, "Expected main archive header"
          end

          @archive_flags = main_header.flags

          # Read blocks until end marker
          loop do
            header = read_header(io)
            break if header.type == block_type_code(:end_marker)

            case header.type
            when block_type_code(:file_header)
              entry = read_file_entry(io, header)
              entries << entry if entry
            when block_type_code(:service_header)
              skip_header_data(io, header)
            when block_type_code(:encryption_header)
              read_encryption_header(io, header)
            else
              skip_header_data(io, header)
            end
          end

          entries
        end

        private

        # Read a RAR v5 header
        #
        # @param io [IO] The input stream
        # @return [HeaderBlock] The header block
        def read_header(io)
          header_crc = io.read(4)&.unpack1("V")
          header_size = read_vint(io)
          header_type = read_vint(io)
          header_flags = read_vint(io)

          # Read extra size if present
          extra_size = 0
          extra_size = read_vint(io) if header_flags & 0x0001 != 0

          # Read data size if present
          data_size = 0
          data_size = read_vint(io) if header_flags & 0x0002 != 0

          HeaderBlock.new(
            crc: header_crc,
            size: header_size,
            type: header_type,
            flags: header_flags,
            extra_size: extra_size,
            data_size: data_size,
            position: io.pos
          )
        end

        # Read a file entry from archive
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The file header
        # @return [Entry] The file entry
        def read_file_entry(io, header)
          flags = read_vint(io)
          unpacked_size = read_vint(io)
          attributes = read_vint(io)

          # Read modification time if present
          mtime = Time.now
          if flags & spec.format.file_header_flags[:time_present] != 0
            mtime = read_file_time(io)
          end

          # Read CRC32 if present
          data_crc = 0
          if flags & spec.format.file_header_flags[:crc32_present] != 0
            data_crc = io.read(4)&.unpack1("V")
          end

          # Read compression info
          compression_flags = read_vint(io)
          host_os = read_vint(io)
          name_length = read_vint(io)

          # Read filename (UTF-8 encoded)
          name_bytes = io.read(name_length)
          filename = name_bytes.force_encoding("UTF-8")

          # Determine if directory
          is_directory = flags.anybits?(spec.format.file_header_flags[:directory])

          # Skip extra area if present
          if header.extra_size.positive?
            skip_bytes = header.extra_size - (io.pos - header.position)
            io.seek(skip_bytes, IO::SEEK_CUR) if skip_bytes.positive?
          end

          # Determine compressed size from data_size
          packed_size = header.data_size

          Entry.new(
            name: filename,
            compressed_size: packed_size,
            uncompressed_size: unpacked_size,
            crc32: data_crc,
            compression_method: extract_compression_method(compression_flags),
            modified_time: mtime,
            attributes: attributes,
            encrypted: header.flags.anybits?(0x0004),
            data_offset: io.pos,
            host_os: host_os,
            is_directory: is_directory
          )
        end

        # Extract compression method from flags
        #
        # @param flags [Integer] The compression flags
        # @return [Symbol] The compression method
        def extract_compression_method(flags)
          method_code = flags & 0x07

          case method_code
          when 0 then :store
          when 1 then :fastest
          when 2 then :fast
          when 3 then :normal
          when 4 then :good
          when 5 then :best
          else :normal
          end
        end

        # Read file time in RAR5 format
        #
        # @param io [IO] The input stream
        # @return [Time] The file time
        def read_file_time(io)
          read_vint(io)

          # Simplified time reading - actual format is more complex
          unix_time = io.read(8)&.unpack1("Q<")
          Time.at(unix_time / 10_000_000.0) if unix_time
        rescue ArgumentError
          Time.now
        end

        # Read encryption header
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The header
        # @return [void]
        def read_encryption_header(io, header)
          # Read and skip encryption data
          skip_header_data(io, header)
        end

        # Skip header data
        #
        # @param io [IO] The input stream
        # @param header [HeaderBlock] The header
        # @return [void]
        def skip_header_data(io, header)
          remaining = header.size - (io.pos - header.position)
          io.seek(remaining, IO::SEEK_CUR) if remaining.positive?

          # Skip data section if present
          io.seek(header.data_size, IO::SEEK_CUR) if header.data_size.positive?
        end
      end

      # RAR v5 header block model
      class HeaderBlock < Lutaml::Model::Serializable
        attribute :crc, :integer
        attribute :size, :integer
        attribute :type, :integer
        attribute :flags, :integer
        attribute :extra_size, :integer
        attribute :data_size, :integer
        attribute :position, :integer
      end

      # RAR v5 archive entry model
      class Entry < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :compressed_size, :integer
        attribute :uncompressed_size, :integer
        attribute :crc32, :integer
        attribute :compression_method, :string
        attribute :modified_time, :string
        attribute :attributes, :integer
        attribute :encrypted, :boolean
        attribute :data_offset, :integer
        attribute :host_os, :integer
        attribute :is_directory, :boolean
      end
    end
  end
end

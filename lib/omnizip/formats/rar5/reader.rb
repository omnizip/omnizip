# frozen_string_literal: true

require "stringio"
require "tmpdir"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 archive reader
      #
      # Adapter over the primary `Formats::Rar::Reader` — the one RAR5
      # parser verified against real archives and unrar — exposing the
      # legacy entry shape (uncompressed_size, modified_time, ...).
      #
      # RAR 5 uses variable-length integers (vint) and improved header structure.
      #
      # @example Reading a RAR5 archive
      #   reader = Rar5::Reader.new
      #   File.open("archive.rar", "rb") do |file|
      #     entries = reader.read_archive(file)
      #     entries.each { |entry| puts entry.name }
      #   end
      class Reader < Omnizip::Formats::Rar::RarFormatBase
        # RAR5 compression-method byte (cinfo bits 8-10) to the legacy
        # symbol vocabulary
        METHOD_SYMBOLS = {
          0x30 => :store,
          0x31 => :fastest,
          0x32 => :fast,
          0x33 => :normal,
          0x34 => :good,
          0x35 => :best,
        }.freeze

        # Initialize a RAR v5 reader
        def initialize
          super("rar5")
        end

        # Read a RAR v5 archive
        #
        # @param io [IO] The input stream
        # @return [Array<Entry>] The archive entries
        # @raise [FormatError] If the archive signature is invalid
        def read_archive(io)
          data = io.read
          unless verify_magic_bytes(StringIO.new(data))
            raise FormatError, "Invalid RAR v5 signature"
          end

          Dir.mktmpdir("omnizip_rar5_read") do |tmp|
            archive_path = File.join(tmp, "archive.rar")
            File.binwrite(archive_path, data)

            primary = Rar::Reader.new(archive_path)
            primary.open
            primary.list_files.map { |entry| adapt_entry(entry) }
          end
        end

        private

        # Map a primary RarEntry onto the legacy Entry shape
        def adapt_entry(entry)
          Entry.new(
            name: entry.name,
            compressed_size: entry.compressed_size,
            uncompressed_size: entry.size,
            crc32: entry.crc,
            compression_method: METHOD_SYMBOLS[entry.method],
            modified_time: entry.mtime,
            attributes: entry.attributes,
            encrypted: entry.encrypted,
            host_os: entry.host_os,
            is_directory: entry.is_dir,
          )
        end

        class HeaderBlock
          attr_accessor :crc, :size, :vint_length, :type, :flags, :extra_size,
                        :data_size, :header_start, :content_start

          def initialize(crc: nil, size: nil, vint_length: 1, type: nil, flags: nil,
                         extra_size: nil, data_size: nil, header_start: nil, content_start: nil)
            @crc = crc
            @size = size
            @vint_length = vint_length
            @type = type
            @flags = flags
            @extra_size = extra_size
            @data_size = data_size
            @header_start = header_start
            @content_start = content_start
          end
        end

        # RAR v5 archive entry model
        class Entry
          include Omnizip::Entry

          attr_accessor :name, :compressed_size, :uncompressed_size, :crc32,
                        :compression_method, :modified_time, :attributes,
                        :encrypted, :data_offset, :host_os, :is_directory

          def entry_name = name
          def entry_directory? = is_directory
          def entry_size = uncompressed_size
          def entry_mtime = modified_time

          def initialize(name: nil, compressed_size: nil, uncompressed_size: nil,
                         crc32: nil, compression_method: nil, modified_time: nil,
                         attributes: nil, encrypted: nil, data_offset: nil,
                         host_os: nil, is_directory: nil)
            @name = name
            @compressed_size = compressed_size
            @uncompressed_size = uncompressed_size
            @crc32 = crc32
            @compression_method = compression_method
            @modified_time = modified_time
            @attributes = attributes
            @encrypted = encrypted
            @data_offset = data_offset
            @host_os = host_os
            @is_directory = is_directory
          end
        end
      end
    end
  end
end

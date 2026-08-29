# frozen_string_literal: true

require "stringio"
require "tmpdir"

module Omnizip
  module Formats
    module Rar3
      # RAR v3 (RAR4-family) archive reader
      #
      # Adapter over the primary `Formats::Rar::Reader` — the one
      # parser verified against real WinRAR archives — exposing the
      # legacy entry shape (uncompressed_size, modified_time, ...).
      #
      # @example Reading a RAR3 archive
      #   reader = Rar3::Reader.new
      #   File.open("archive.rar", "rb") do |file|
      #     reader.read_archive(file).each { |entry| puts entry.name }
      #   end
      class Reader < Omnizip::Formats::Rar::RarFormatBase
        # RAR4 method byte to the legacy symbol vocabulary
        METHOD_SYMBOLS = {
          0x30 => :store,
          0x31 => :fastest,
          0x32 => :fast,
          0x33 => :normal,
          0x34 => :good,
          0x35 => :best,
        }.freeze

        # Initialize a RAR v3 reader
        def initialize
          super("rar3")
        end

        # Read a RAR v3 archive
        #
        # @param io [IO] The input stream
        # @return [Array<Entry>] The archive entries
        # @raise [FormatError] If the archive signature is invalid
        def read_archive(io)
          data = io.read
          unless verify_magic_bytes(StringIO.new(data))
            raise FormatError, "Invalid RAR v3 signature"
          end

          Dir.mktmpdir("omnizip_rar3_read") do |tmp|
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
          )
        end

        # RAR archive entry model (legacy shape)
        class Entry
          include Omnizip::Entry

          attr_accessor :name, :compressed_size, :uncompressed_size, :crc32,
                        :compression_method, :modified_time, :attributes,
                        :encrypted, :data_offset, :host_os, :salt

          def entry_name = name
          def entry_directory? = false
          def entry_size = uncompressed_size
          def entry_mtime = modified_time

          def initialize(name: nil, compressed_size: nil, uncompressed_size: nil,
                         crc32: nil, compression_method: nil, modified_time: nil,
                         attributes: nil, encrypted: nil, data_offset: nil,
                         host_os: nil, salt: nil)
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
            @salt = salt
          end
        end
      end
    end
  end
end

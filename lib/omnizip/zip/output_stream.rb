# frozen_string_literal: true

require "fileutils"
require_relative "../formats/zip/constants"
require_relative "../formats/zip/local_file_header"
require_relative "../formats/zip/central_directory_header"
require_relative "../formats/zip/end_of_central_directory"

module Omnizip
  module Zip
    # Rubyzip-compatible OutputStream class
    # Provides streaming write API for ZIP archives
    class OutputStream
      include Omnizip::Formats::Zip::Constants

      # Open a new output stream
      # @param file_path [String] Path to ZIP file
      # @yield [stream] Block to write to the stream
      # @return [OutputStream] The stream (if no block given)
      def self.open(file_path, &block)
        stream = new(file_path)

        if block
          begin
            yield(stream)
          ensure
            stream.close
          end
        else
          stream
        end
      end

      # Initialize output stream
      # @param file_path_or_io [String, IO] File path or IO object
      def initialize(file_path_or_io)
        if file_path_or_io.is_a?(String)
          @file_path = file_path_or_io
          @io = ::File.open(file_path_or_io, "wb")
          @owns_io = true
        else
          @io = file_path_or_io
          @owns_io = false
        end

        @entries = []
        @current_entry = nil
        @current_entry_data = nil
        @closed = false
      end

      # Start a new entry
      # @param name [String] Entry name
      # @param time [Time] Modification time
      # @param comment [String] Entry comment
      # @param compression [Symbol] Compression method (:store or :deflate)
      # @param level [Integer] Compression level (1-9)
      def put_next_entry(name, time: Time.now, comment: "",
compression: :deflate, level: 6)
        close_entry if @current_entry

        @current_entry = {
          name: name,
          time: time,
          comment: comment,
          compression: compression_method_for(compression),
          level: level,
          offset: @io.pos,
          directory: name.end_with?("/"),
        }
        @current_entry_data = String.new(encoding: Encoding::BINARY)

        # Write placeholder local file header (will update later)
        write_local_file_header_placeholder

        self
      end

      # Write data to current entry
      # @param data [String] Data to write
      def write(data)
        raise "No entry started. Call put_next_entry first" unless @current_entry

        @current_entry_data << data.b
        self
      end
      alias_method :<<, :write

      # Print data to current entry
      def print(*args)
        write(args.join)
      end

      # Put data to current entry
      def puts(*args)
        args.each { |arg| write("#{arg}\n") }
      end

      # Close current entry
      def close_entry
        return unless @current_entry

        # Compress data if needed
        compressed_data = compress_entry_data

        # Calculate CRC32
        crc32 = @current_entry[:directory] ? 0 : calculate_crc32(@current_entry_data)

        # Write compressed data
        @io.write(compressed_data) unless @current_entry[:directory]

        # Update entry info
        @current_entry.merge!({
                                crc32: crc32,
                                compressed_size: compressed_data.bytesize,
                                uncompressed_size: @current_entry_data.bytesize,
                              })

        # Update local file header with correct sizes
        current_pos = @io.pos
        @io.seek(@current_entry[:offset], ::IO::SEEK_SET)
        write_local_file_header
        @io.seek(current_pos, ::IO::SEEK_SET)

        # Save entry for central directory
        @entries << @current_entry

        @current_entry = nil
        @current_entry_data = nil
      end

      # Set archive comment
      def comment=(comment)
        @comment = comment
      end

      # Get archive comment
      def comment
        @comment || ""
      end

      # Close the stream
      def close
        return if @closed

        close_entry if @current_entry

        # Write central directory
        central_directory_offset = @io.pos
        write_central_directory
        central_directory_size = @io.pos - central_directory_offset

        # Write end of central directory
        write_end_of_central_directory(central_directory_offset,
                                       central_directory_size)

        @io.close if @owns_io
        @closed = true
      end

      # Check if stream is closed
      def closed?
        @closed
      end

      private

      # Get compression method code
      def compression_method_for(symbol)
        case symbol
        when :store, :none then COMPRESSION_STORE
        when :deflate then COMPRESSION_DEFLATE
        when :bzip2 then COMPRESSION_BZIP2
        when :lzma then COMPRESSION_LZMA
        when :zstandard then COMPRESSION_ZSTANDARD
        else COMPRESSION_DEFLATE
        end
      end

      # Write local file header placeholder
      def write_local_file_header_placeholder
        # Write zeros for now, will update after compression
        @io.write("\x00" * 30) # Fixed part
        @io.write(@current_entry[:name].b) # Filename
        @current_entry[:filename_length] = @current_entry[:name].bytesize
        @current_entry[:extra_field_length] = 0
      end

      # Write actual local file header
      def write_local_file_header
        header = Omnizip::Formats::Zip::LocalFileHeader.new(
          version_needed: version_for_method(@current_entry[:compression]),
          flags: FLAG_UTF8,
          compression_method: @current_entry[:directory] ? COMPRESSION_STORE : @current_entry[:compression],
          last_mod_time: dos_time(@current_entry[:time]),
          last_mod_date: dos_date(@current_entry[:time]),
          crc32: @current_entry[:crc32],
          compressed_size: @current_entry[:compressed_size],
          uncompressed_size: @current_entry[:uncompressed_size],
          filename: @current_entry[:name],
        )

        @io.write(header.to_binary)
      end

      # Compress current entry data
      def compress_entry_data
        return "" if @current_entry[:directory]

        case @current_entry[:compression]
        when COMPRESSION_STORE
          @current_entry_data
        when COMPRESSION_DEFLATE
          compress_deflate(@current_entry_data, @current_entry[:level])
        when COMPRESSION_BZIP2
          compress_bzip2(@current_entry_data, @current_entry[:level])
        when COMPRESSION_LZMA
          compress_lzma(@current_entry_data, @current_entry[:level])
        when COMPRESSION_ZSTANDARD
          compress_zstandard(@current_entry_data, @current_entry[:level])
        else
          @current_entry_data
        end
      end

      # Write central directory
      def write_central_directory
        @entries.each do |entry|
          external_attrs = if entry[:directory]
                             UNIX_DIR_PERMISSIONS | ATTR_DIRECTORY
                           else
                             UNIX_FILE_PERMISSIONS
                           end

          header = Omnizip::Formats::Zip::CentralDirectoryHeader.new(
            version_made_by: VERSION_MADE_BY_UNIX | version_for_method(entry[:compression]),
            version_needed: version_for_method(entry[:compression]),
            flags: FLAG_UTF8,
            compression_method: entry[:directory] ? COMPRESSION_STORE : entry[:compression],
            last_mod_time: dos_time(entry[:time]),
            last_mod_date: dos_date(entry[:time]),
            crc32: entry[:crc32],
            compressed_size: entry[:compressed_size],
            uncompressed_size: entry[:uncompressed_size],
            disk_number_start: 0,
            internal_attributes: 0,
            external_attributes: external_attrs,
            local_header_offset: entry[:offset],
            filename: entry[:name],
            extra_field: "",
            comment: entry[:comment] || "",
          )

          @io.write(header.to_binary)
        end
      end

      # Write end of central directory
      def write_end_of_central_directory(offset, size)
        eocd = Omnizip::Formats::Zip::EndOfCentralDirectory.new(
          disk_number: 0,
          disk_number_with_cd: 0,
          total_entries_this_disk: @entries.size,
          total_entries: @entries.size,
          central_directory_size: size,
          central_directory_offset: offset,
          comment: comment,
        )

        @io.write(eocd.to_binary)
      end

      # Compress using Deflate
      def compress_deflate(data, level)
        require "zlib"
        Zlib::Deflate.new(level, -Zlib::MAX_WBITS).deflate(data, Zlib::FINISH)
      end

      # Compress using BZip2
      def compress_bzip2(data, level)
        algorithm = Omnizip::AlgorithmRegistry.get(:bzip2)
        algorithm.compress(data, level: level)
      end

      # Compress using LZMA
      def compress_lzma(data, level)
        algorithm = Omnizip::AlgorithmRegistry.get(:lzma)
        algorithm.compress(data, level: level)
      end

      # Compress using Zstandard
      def compress_zstandard(data, level)
        algorithm = Omnizip::AlgorithmRegistry.get(:zstandard)
        algorithm.compress(data, level: level)
      end

      # Calculate CRC32
      def calculate_crc32(data)
        Omnizip::Checksums::Crc32.new.tap { |c| c.update(data) }.finalize
      end

      # Get version needed for compression method
      def version_for_method(method)
        case method
        when COMPRESSION_STORE then VERSION_DEFAULT
        when COMPRESSION_DEFLATE then VERSION_DEFLATE
        when COMPRESSION_BZIP2 then VERSION_BZIP2
        when COMPRESSION_LZMA then VERSION_LZMA
        else VERSION_DEFAULT
        end
      end

      # Convert Time to DOS time
      def dos_time(time)
        ((time.hour << 11) | (time.min << 5) | (time.sec / 2)) & 0xFFFF
      end

      # Convert Time to DOS date
      def dos_date(time)
        (((time.year - 1980) << 9) | (time.month << 5) | time.day) & 0xFFFF
      end
    end
  end
end

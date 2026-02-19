# frozen_string_literal: true

require_relative "entry"
require_relative "../formats/zip/constants"
require_relative "../formats/zip/local_file_header"

module Omnizip
  module Zip
    # Rubyzip-compatible InputStream class
    # Provides streaming read API for ZIP archives
    class InputStream
      include Omnizip::Formats::Zip::Constants

      # Open an input stream
      # @param file_path_or_io [String, IO] File path or IO object
      # @yield [stream] Block to read from the stream
      # @return [InputStream] The stream (if no block given)
      def self.open(file_path_or_io, &block)
        stream = new(file_path_or_io)

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

      # Initialize input stream
      # @param file_path_or_io [String, IO] File path or IO object
      def initialize(file_path_or_io)
        if file_path_or_io.is_a?(String)
          @file_path = file_path_or_io
          @io = ::File.open(file_path_or_io, "rb")
          @owns_io = true
        else
          @io = file_path_or_io
          @owns_io = false
        end

        @current_entry = nil
        @current_entry_io = nil
        @current_index = 0
        @closed = false
        @hit_nil = false

        # Find and parse central directory for efficient access
        parse_central_directory
      end

      # Get next entry in the archive
      # @return [Entry, nil] Next entry or nil if no more entries
      def get_next_entry
        # Check if we can fetch another entry
        if @current_index >= @all_entries.size
          # Mark that get_next_entry returned nil
          @hit_nil = true
          return nil
        end

        # Close previous entry data if open
        @current_entry_io = nil

        # Get next entry from our parsed list
        header = @all_entries[@current_index]
        @current_index += 1

        # Successfully got an entry - clear the nil flag
        @hit_nil = false

        # Position at entry data
        position_at_entry_data(header)

        @current_entry = Entry.new(header)
        @current_entry
      end

      # Read from current entry
      # @param size [Integer, nil] Number of bytes to read (nil for all)
      # @return [String, nil] Data read or nil if no current entry
      def read(size = nil)
        return nil unless @current_entry

        # Initialize entry IO if needed
        unless @current_entry_io
          compressed_data = @io.read(@current_entry.compressed_size)
          decompressed = decompress_data(
            compressed_data,
            @current_entry.compression_method,
            @current_entry.size,
          )
          require "stringio"
          @current_entry_io = StringIO.new(decompressed, "rb")
        end

        @current_entry_io.read(size)
      end

      # Rewind the stream
      def rewind
        @current_index = 0
        @current_entry = nil
        @current_entry_io = nil
        @hit_nil = false
      end

      # Close the stream
      def close
        return if @closed

        @current_entry_io = nil
        @io.close if @owns_io
        @closed = true
      end

      # Check if stream is closed
      def closed?
        @closed
      end

      # Check if at end of file
      # Returns true if the NEXT call to get_next_entry would return nil
      def eof?
        @current_index >= @all_entries.size
      end
      alias_method :eof, :eof?

      private

      # Parse central directory to get all entries
      def parse_central_directory
        # Find End of Central Directory
        eocd = find_eocd

        # Read central directory entries
        @io.seek(eocd[:central_directory_offset], ::IO::SEEK_SET)
        @all_entries = []

        eocd[:total_entries].times do
          header_data = @io.read(46)
          break unless header_data && header_data.size == 46

          # Get dynamic field lengths
          _, _, _, _, _, _, _, _, _, _,
          filename_length, extra_field_length, comment_length = header_data.unpack("VvvvvvvVVVvvv")

          # Read complete header
          complete_data = header_data + @io.read(filename_length + extra_field_length + comment_length)
          entry = Omnizip::Formats::Zip::CentralDirectoryHeader.from_binary(complete_data)

          @all_entries << entry
        end
      end

      # Find End of Central Directory record
      def find_eocd
        # Start from end of file
        @io.seek(0, ::IO::SEEK_END)
        file_size = @io.pos

        # EOCD is at least 22 bytes
        return nil if file_size < 22

        # Search backwards for EOCD signature
        # Maximum comment length is 65535, so search up to 65557 bytes from end
        search_start = [file_size - 65557, 0].max
        @io.seek(search_start, ::IO::SEEK_SET)
        buffer = @io.read

        # Find signature
        signature = [END_OF_CENTRAL_DIRECTORY_SIGNATURE].pack("V")
        pos = buffer.rindex(signature)

        unless pos
          raise Omnizip::FormatError,
                "End of Central Directory not found"
        end

        # Parse EOCD
        eocd_data = buffer[pos..]

        sig, disk_num, disk_with_cd, entries_this_disk, total_entries,
        cd_size, cd_offset, comment_length = eocd_data.unpack("VvvvvVVv")

        {
          signature: sig,
          disk_number: disk_num,
          disk_number_with_cd: disk_with_cd,
          total_entries_this_disk: entries_this_disk,
          total_entries: total_entries,
          central_directory_size: cd_size,
          central_directory_offset: cd_offset,
          comment_length: comment_length,
          comment: eocd_data[22, comment_length] || "",
        }
      end

      # Position IO at entry's data (after local file header)
      def position_at_entry_data(header)
        # Seek to local file header
        @io.seek(header.local_header_offset, ::IO::SEEK_SET)

        # Read fixed part of local file header
        fixed_header = @io.read(30)

        # Extract variable lengths
        _, _, _, _, _, _, _, _, _, filename_length, extra_length =
          fixed_header.unpack("VvvvvvVVVvv")

        # Skip variable parts to get to data
        @io.read(filename_length + extra_length)
      end

      # Decompress data based on compression method
      def decompress_data(compressed_data, method, uncompressed_size)
        case method
        when COMPRESSION_STORE
          compressed_data
        when COMPRESSION_DEFLATE
          decompress_deflate(compressed_data)
        when COMPRESSION_BZIP2
          decompress_bzip2(compressed_data)
        when COMPRESSION_LZMA
          decompress_lzma(compressed_data, uncompressed_size)
        when COMPRESSION_ZSTANDARD
          decompress_zstandard(compressed_data)
        else
          raise Omnizip::UnsupportedFormatError,
                "Unsupported compression method: #{method}"
        end
      end

      # Decompress using Deflate
      def decompress_deflate(data)
        require "zlib"
        Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data)
      rescue StandardError => e
        raise Omnizip::DecompressionError,
              "Deflate decompression failed: #{e.message}"
      end

      # Decompress using BZip2
      def decompress_bzip2(data)
        algorithm = Omnizip::AlgorithmRegistry.get(:bzip2)
        algorithm.decompress(data)
      rescue StandardError => e
        raise Omnizip::DecompressionError,
              "BZip2 decompression failed: #{e.message}"
      end

      # Decompress using LZMA
      def decompress_lzma(data, uncompressed_size)
        algorithm = Omnizip::AlgorithmRegistry.get(:lzma)
        algorithm.decompress(data, uncompressed_size: uncompressed_size)
      rescue StandardError => e
        raise Omnizip::DecompressionError,
              "LZMA decompression failed: #{e.message}"
      end

      # Decompress using Zstandard
      def decompress_zstandard(data)
        algorithm = Omnizip::AlgorithmRegistry.get(:zstandard)
        algorithm.decompress(data)
      rescue StandardError => e
        raise Omnizip::DecompressionError,
              "Zstandard decompression failed: #{e.message}"
      end
    end
  end
end

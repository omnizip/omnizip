# frozen_string_literal: true

require_relative "xz_impl/constants"
require_relative "xz_impl/stream_encoder"
require_relative "xz_impl/writer"
require_relative "xz/reader"
require_relative "../algorithms/lzma"

module Omnizip
  module Formats
    # XZ compression format
    # Creates .xz files compatible with XZ Utils
    class Xz
      class << self
        # Create a .xz file from input data
        # @param input [String, IO] Input data to compress
        # @param output [String, IO] Output file path or IO object
        # @param options [Hash] Compression options
        # @option options [Integer] :dict_size Dictionary size (default: 8MB to match XZ Utils preset 6)
        # @option options [Integer] :check Check type (default: CRC64)
        def create(input, output = nil, options = {})
          encoder = XzFormat::StreamEncoder.new(
            check_type: options[:check] || XzConst::CHECK_CRC64,
            dict_size: options[:dict_size] || (64 * 1024 * 1024),
          )

          compressed = encoder.encode(input)

          if output
            if output.respond_to?(:write)
              output.write(compressed)
            else
              File.binwrite(output, compressed)
            end
          else
            compressed
          end
        end

        # Convenience method with block syntax
        # @example
        #   Xz.create_file('output.xz') do |xz|
        #     xz.add_data('Hello, XZ!')
        #   end
        def create_file(path, options = {})
          builder = Builder.new(options)
          yield builder if block_given?

          compressed = create(builder.data, nil, options)
          File.binwrite(path, compressed)
        end

        # Decode XZ data (alias for decompress with no output)
        # @param input [String, IO] Input XZ data or file path
        # @return [String] Decompressed data
        def decode(input)
          decompress(input)
        end

        # Decompress XZ, LZIP (.lz), or LZMA_Alone (.lzma) data
        #
        # This method automatically detects the format based on magic bytes and
        # routes to the appropriate decoder:
        # - XZ format (.xz): Container format with stream header/footer/index
        # - LZIP format (.lz): Standalone format with "LZIP" magic and CRC32 footer
        # - LZMA_Alone format (.lzma): Legacy standalone format with properties byte
        #
        # @param input [String, IO] Input data or file path
        # @param output [String, IO, nil] Output file path or IO object
        # @param options [Hash] Options (reserved for future use)
        # @return [String, nil] Decompressed data (if output is nil)
        def decompress(input, output = nil, _options = {})
          # Handle raw data string vs file path
          data = if input.respond_to?(:read)
                   # Already an IO object - read content
                   if input.respond_to?(:size)
                     # Seekable IO (File, etc.) - read without consuming
                     original_pos = input.pos
                     content = input.read
                     input.seek(original_pos)
                   else
                     # Non-seekable IO - read and consume
                     content = input.read
                   end
                   content
                 elsif input.is_a?(String)
                   # Could be file path or raw data
                   # If string contains null byte, it's definitely data (not a path)
                   # Also check if it's a valid file path first
                   if !input.include?("\0") && File.exist?(input)
                     File.binread(input)
                   else
                     input.b
                   end
                 else
                   raise ArgumentError,
                         "Input must be a String or IO object"
                 end

          # Detect format and decode
          decompressed = decode_lzma_data(data)

          if output
            if output.respond_to?(:write)
              output.write(decompressed)
            else
              File.binwrite(output, decompressed)
            end
            nil
          else
            decompressed
          end
        end

        private

        # Decode LZMA-based data by detecting format
        # @param data [String] Input data
        # @return [String] Decompressed data
        def decode_lzma_data(data)
          format = detect_lzma_format(data)

          case format
          when :lz
            decode_lzip(data)
          when :lzma_alone
            decode_lzma_alone(data)
          when :xz
            decode_xz_stream(data)
          else
            raise FormatError, "Unknown LZMA format: cannot detect valid format"
          end
        end

        # Detect LZMA format from magic bytes
        # @param data [String] Input data
        # @return [Symbol] Format type (:xz, :lz, :lzma_alone)
        def detect_lzma_format(data)
          return :unknown if data.nil? || data.bytesize < 4

          first_bytes = data.byteslice(0, 6).bytes.to_a

          # Check XZ magic: FD 37 7A 58 5A 00
          # Reference: xz-file-format-1.2.1.txt Section 2.1.1.1
          if first_bytes[0] == 0xFD && first_bytes[1] == 0x37 &&
              first_bytes[2] == 0x7A && first_bytes[3] == 0x58 &&
              first_bytes[4] == 0x5A && first_bytes[5].zero?
            return :xz
          end

          # Check LZIP magic: 4C 5A 49 50 ("LZIP")
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/lzip_decoder.c:106
          if first_bytes[0] == 0x4C && first_bytes[1] == 0x5A &&
              first_bytes[2] == 0x49 && first_bytes[3] == 0x50
            return :lz
          end

          # Default to LZMA_Alone (legacy format, no magic bytes)
          # The format starts with properties byte, dictionary size, and uncompressed size
          # Reference: /Users/mulgogi/src/external/xz/src/liblzma/common/alone_decoder.c
          :lzma_alone
        end

        # Decode LZIP format (.lz files)
        # @param data [String] Input data
        # @return [String] Decompressed data
        def decode_lzip(data)
          input = StringIO.new(data)
          decoder = Omnizip::Algorithms::LZMA::LzipDecoder.new(input)
          decoder.decode_stream
        rescue StandardError => e
          raise FormatError, "Failed to decode LZIP format: #{e.message}"
        end

        # Decode LZMA_Alone format (.lzma files)
        # @param data [String] Input data
        # @return [String] Decompressed data
        def decode_lzma_alone(data)
          input = StringIO.new(data)
          decoder = Omnizip::Algorithms::LZMA::LzmaAloneDecoder.new(input)
          decoder.decode_stream
        rescue StandardError => e
          raise FormatError, "Failed to decode LZMA_Alone format: #{e.message}"
        end

        # Decode XZ format stream
        # @param data [String] Input data
        # @return [String] Decompressed data
        def decode_xz_stream(data)
          input_io = StringIO.new(data.b)
          reader = Reader.new(input_io)
          reader.read
        rescue StandardError => e
          raise FormatError, "Failed to decode XZ format: #{e.message}"
        end

        # Alias for compatibility
        alias decode decompress
        alias extract decompress

        # Entry method for archive-like interface
        # @param input [String, IO] Input XZ data or file path
        # @param options [Hash] Options (reserved)
        # @yield [Entry] Yields entry (XZ has single data stream)
        # @return [String, Entry] Decompressed data or Entry if no block given
        def extract_entry(input, options = {})
          data = decompress(input, nil, options)

          entry = Entry.new(data)
          if block_given?
            yield entry
          else
            entry
          end
        end
      end

      # Builder class for convenient file creation
      class Builder
        attr_reader :data

        def initialize(_options = {})
          @data = String.new(encoding: Encoding::BINARY)
        end

        def add_data(content)
          @data << content.to_s.dup.force_encoding(Encoding::BINARY)
        end

        def add_file(path)
          content = File.binread(path)
          add_data(content)
        end
      end
    end
  end
end

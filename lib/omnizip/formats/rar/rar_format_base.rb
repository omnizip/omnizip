# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

require_relative "../format_spec_loader"

module Omnizip
  module Formats
    module Rar
      # Base class for RAR format implementations
      #
      # This class provides common functionality for RAR v3 and RAR v5 formats,
      # following the Strategy pattern where each version has its own
      # implementation strategy.
      #
      # @abstract Subclass and override {#read_archive}, {#write_archive},
      #   {#compress}, and {#decompress} to implement a RAR version strategy.
      class RarFormatBase
        attr_reader :spec, :version

        # Initialize a RAR format handler
        #
        # @param spec_name [String] The format specification name
        #   (e.g., "rar3", "rar5")
        def initialize(spec_name)
          @spec = FormatSpecLoader.load(spec_name)
          @version = @spec.version
        end

        # Read a RAR archive
        #
        # @param io [IO] The input stream
        # @return [Array<Entry>] The archive entries
        # @raise [NotImplementedError] Must be implemented by subclasses
        def read_archive(io)
          raise NotImplementedError,
                "#{self.class} must implement #read_archive"
        end

        # Write a RAR archive
        #
        # @param io [IO] The output stream
        # @param entries [Array<Entry>] The entries to write
        # @return [void]
        # @raise [NotImplementedError] Must be implemented by subclasses
        def write_archive(io, entries)
          raise NotImplementedError,
                "#{self.class} must implement #write_archive"
        end

        # Compress data
        #
        # @param data [String] The data to compress
        # @param method [Symbol] The compression method
        # @param options [Hash] Compression options
        # @return [String] The compressed data
        # @raise [NotImplementedError] Must be implemented by subclasses
        def compress(data, method: :normal, **options)
          raise NotImplementedError,
                "#{self.class} must implement #compress"
        end

        # Decompress data
        #
        # @param data [String] The compressed data
        # @param method [Symbol] The compression method
        # @param options [Hash] Decompression options
        # @return [String] The decompressed data
        # @raise [NotImplementedError] Must be implemented by subclasses
        def decompress(data, method: :normal, **options)
          raise NotImplementedError,
                "#{self.class} must implement #decompress"
        end

        # Verify magic bytes match this format
        #
        # @param io [IO] The input stream
        # @return [Boolean] True if magic bytes match
        def verify_magic_bytes(io)
          magic = spec.magic_bytes.pack("C*")
          bytes = io.read(magic.bytesize)
          io.rewind
          bytes == magic
        end

        # Get compression method code from symbol
        #
        # @param method [Symbol] The method name (e.g., :normal, :best)
        # @return [Integer] The method code
        # @raise [FormatError] If method is not supported
        def compression_method_code(method)
          code = spec.format.compression_methods[method]
          return code if code

          raise FormatError,
                "Unsupported compression method: #{method}"
        end

        # Get compression method symbol from code
        #
        # @param code [Integer] The method code
        # @return [Symbol] The method name
        # @raise [FormatError] If code is not recognized
        def compression_method_name(code)
          methods = spec.format.compression_methods
          name = methods.key(code)
          return name if name

          # Handle unknown method codes gracefully
          # RAR can have version-specific or PPMd methods not in standard list
          case code
          when 0x00..0x2F then :store      # Very old or stored
          when 0x30 then :store
          when 0x31 then :fastest
          when 0x32 then :fast
          when 0x33 then :normal
          when 0x34 then :good
          when 0x35 then :best
          when 0x36..0x40 then :normal     # Extended range
          when 0x80..0xFF then :ppmd       # PPMd or version-specific
          else :unknown
          end
        end

        # Get block type code from symbol
        #
        # @param type [Symbol] The block type name
        # @return [Integer] The block type code
        # @raise [FormatError] If type is not supported
        def block_type_code(type)
          code = spec.format.block_types[type]
          return code if code

          raise FormatError, "Unknown block type: #{type}"
        end

        # Get block type symbol from code
        #
        # @param code [Integer] The block type code
        # @return [Symbol] The block type name
        # @raise [FormatError] If code is not recognized
        def block_type_name(code)
          types = spec.format.block_types
          name = types.key(code)
          return name if name

          raise FormatError, "Unknown block type code: #{code}"
        end

        # Check if format supports a feature
        #
        # @param feature [Symbol] The feature name
        # @return [Boolean] True if supported
        def supports_feature?(feature)
          features = spec.format.features || {}
          compression_features = spec.format.compression_features || {}
          advanced_features = spec.format.advanced_features || {}

          features[feature] ||
            compression_features[feature] ||
            advanced_features[feature] ||
            false
        end

        # Get encryption algorithm
        #
        # @return [String, nil] The encryption algorithm or nil
        def encryption_algorithm
          return nil unless spec.format.encryption&.supported

          algorithms = spec.format.encryption.algorithms
          algorithms&.first
        end

        # Get dictionary size for compression level
        #
        # @param level [Symbol] The compression level
        # @return [Integer] The dictionary size code
        def dictionary_size_code(level)
          spec.format.dictionary_sizes[level] ||
            spec.format.dictionary_sizes[:auto]
        end

        protected

        # Read a vint (variable-length integer) from stream
        #
        # Used in RAR 5 format for variable-length encoding
        #
        # @param io [IO] The input stream
        # @return [Integer] The decoded integer
        def read_vint(io)
          result = 0
          shift = 0

          loop do
            byte = io.read(1)&.unpack1("C")
            raise FormatError, "Unexpected EOF" unless byte

            result |= (byte & 0x7F) << shift
            break if byte.nobits?(0x80)

            shift += 7
          end

          result
        end

        # Write a vint (variable-length integer) to stream
        #
        # @param io [IO] The output stream
        # @param value [Integer] The value to encode
        # @return [void]
        def write_vint(io, value)
          loop do
            byte = value & 0x7F
            value >>= 7

            byte |= 0x80 if value.positive?
            io.write([byte].pack("C"))

            break if value.zero?
          end
        end

        # Calculate CRC32 checksum
        #
        # @param data [String] The data to checksum
        # @return [Integer] The CRC32 value
        def calculate_crc32(data)
          require "zlib"
          Zlib.crc32(data)
        end
      end
    end
  end
end

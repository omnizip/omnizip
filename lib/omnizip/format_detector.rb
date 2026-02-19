# frozen_string_literal: true

module Omnizip
  # Detects archive format from file signature/magic bytes
  #
  # This class identifies archive formats based on their file signatures.
  # It distinguishes between XZ Utils format (.xz) and 7-Zip format (.7z)
  # which are DIFFERENT implementations of LZMA/LZMA2 compression.
  #
  # @example Basic usage
  #   format = Omnizip::FormatDetector.detect("archive.xz")
  #   case format
  #   when :xz
  #     # Use XZ Utils implementation
  #   when :seven_zip
  #     # Use 7-Zip implementation
  #   end
  #
  class FormatDetector
    # XZ Utils format signature: "\xFD7zXZ\x00"
    XZ_SIGNATURE = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].freeze

    # 7-Zip format signature: "7z\xBC\xAF\x27\x1C"
    SEVEN_ZIP_SIGNATURE = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].freeze

    # RAR5 format signature: "Rar!\x1A\x07\x01\x00"
    RAR5_SIGNATURE = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].freeze

    # RAR4 format signature: "Rar!\x1A\x07\x00"
    RAR4_SIGNATURE = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00].freeze

    # ZIP format signature: "PK\x03\x04"
    ZIP_SIGNATURE = [0x50, 0x4B, 0x03, 0x04].freeze

    # GZIP format signature: "\x1F\x8B"
    GZIP_SIGNATURE = [0x1F, 0x8B].freeze

    # BZIP2 format signature: "BZ"
    BZIP2_SIGNATURE = [0x42, 0x5A].freeze

    # Detect archive format from file path
    #
    # @param file_path [String] Path to the archive file
    # @return [Symbol, nil] Format identifier (:xz, :seven_zip, :rar5, :rar4,
    #   :zip, :gzip, :bzip2, :lzma_alone) or nil if unknown
    def self.detect(file_path)
      return nil unless File.exist?(file_path)

      header = File.binread(file_path, 16)
      return nil if header.nil? || header.empty?

      bytes = header.bytes

      case bytes
      in [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00, *]
        :xz
      in [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, *]
        :seven_zip
      in [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00, *]
        :rar5
      in [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, *]
        :rar4
      in [0x50, 0x4B, 0x03, 0x04, *]
        :zip
      in [0x1F, 0x8B, *]
        :gzip
      in [0x42, 0x5A, *]
        :bzip2
      else
        # Check for LZMA_Alone format (13-byte header with properties)
        detect_lzma_alone(bytes)
      end
    end

    # Check if file is XZ Utils format
    #
    # @param file_path [String] Path to the file
    # @return [Boolean] true if XZ format
    def self.xz?(file_path)
      detect(file_path) == :xz
    end

    # Check if file is 7-Zip format
    #
    # @param file_path [String] Path to the file
    # @return [Boolean] true if 7-Zip format
    def self.seven_zip?(file_path)
      detect(file_path) == :seven_zip
    end

    # Check if file is RAR5 format
    #
    # @param file_path [String] Path to the file
    # @return [Boolean] true if RAR5 format
    def self.rar5?(file_path)
      detect(file_path) == :rar5
    end

    # Check if file is RAR4 format
    #
    # @param file_path [String] Path to the file
    # @return [Boolean] true if RAR4 format
    def self.rar4?(file_path)
      detect(file_path) == :rar4
    end

    # Get the appropriate reader class for the format
    #
    # @param file_path [String] Path to the archive file
    # @return [Class, nil] Reader class or nil if unknown format
    def self.reader_for(file_path)
      case detect(file_path)
      when :xz
        require_relative "formats/xz"
        Omnizip::Formats::Xz
      when :seven_zip
        require_relative "formats/seven_zip/reader"
        Omnizip::Formats::SevenZip::Reader
      when :rar5
        require_relative "formats/rar5/reader"
        Omnizip::Formats::Rar5::Reader
      when :rar4
        require_relative "formats/rar3/reader"
        Omnizip::Formats::Rar3::Reader
      when :zip
        require_relative "formats/zip/reader"
        Omnizip::Formats::Zip::Reader
      end
    end

    # Detect LZMA_Alone format
    #
    # LZMA_Alone format has a 13-byte header:
    # - 1 byte: properties (lc, lp, pb encoded)
    # - 4 bytes: dictionary size (little-endian)
    # - 8 bytes: uncompressed size (little-endian, -1 for unknown)
    #
    # @param bytes [Array<Integer>] First bytes of file
    # @return [Symbol, nil] :lzma_alone or nil
    def self.detect_lzma_alone(bytes)
      return nil if bytes.size < 13

      # Check properties byte (must be valid lc/lp/pb encoding)
      props = bytes[0]
      return nil if props > 225 # Max valid value is (9 * 5 * 5) - 1 = 224

      lc = props % 9
      lp = (props / 9) % 5
      pb = props / 45

      # Validate ranges
      return nil if lc > 8 || lp > 4 || pb > 4

      # Dictionary size should be power of 2 or close to it
      dict_size = bytes[1, 4].pack("C*").unpack1("V")
      return nil if dict_size.zero? || dict_size > (1 << 30) # Max ~1GB

      :lzma_alone
    end
    private_class_method :detect_lzma_alone
  end
end

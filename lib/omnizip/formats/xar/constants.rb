# frozen_string_literal: true

module Omnizip
  module Formats
    module Xar
      # XAR format constants
      #
      # XAR (eXtensible ARchive) format is used primarily on macOS
      # for software distribution (pkg files, etc.)
      #
      # Format structure:
      #   - Header (28 bytes)
      #   - Compressed TOC (Table of Contents, XML)
      #   - TOC Checksum
      #   - Heap (file data)
      module Constants
        # XAR magic number: "xar!" in big-endian
        MAGIC = 0x78617221
        MAGIC_BYTES = "xar!".b

        # Header size (bytes)
        HEADER_SIZE = 28

        # Extended header size (with custom checksum name)
        HEADER_SIZE_EX = 28 + 36

        # Format version
        XAR_VERSION = 1

        # Checksum algorithms
        CKSUM_NONE   = 0
        CKSUM_SHA1   = 1
        CKSUM_MD5    = 2
        CKSUM_OTHER  = 3 # Custom checksum (name in header)

        # Checksum names mapping
        CHECKSUM_NAMES = {
          CKSUM_NONE => "none",
          CKSUM_SHA1 => "sha1",
          CKSUM_MD5 => "md5",
        }.freeze

        CHECKSUM_ALGORITHMS = {
          "none" => CKSUM_NONE,
          "sha1" => CKSUM_SHA1,
          "md5" => CKSUM_MD5,
          "sha224" => CKSUM_OTHER,
          "sha256" => CKSUM_OTHER,
          "sha384" => CKSUM_OTHER,
          "sha512" => CKSUM_OTHER,
        }.freeze

        # Checksum sizes (bytes)
        CHECKSUM_SIZES = {
          "md5" => 16,
          "sha1" => 20,
          "sha224" => 28,
          "sha256" => 32,
          "sha384" => 48,
          "sha512" => 64,
        }.freeze

        # Compression types (used in TOC XML)
        COMPRESSION_NONE   = "none"
        COMPRESSION_GZIP   = "gzip"
        COMPRESSION_BZIP2  = "bzip2"
        COMPRESSION_LZMA   = "lzma"
        COMPRESSION_XZ     = "xz"

        # Compression MIME types (as appear in TOC)
        COMPRESSION_MIME_TYPES = {
          COMPRESSION_NONE => "application/octet-stream",
          COMPRESSION_GZIP => "application/x-gzip",
          COMPRESSION_BZIP2 => "application/x-bzip2",
          COMPRESSION_LZMA => "application/x-lzma",
          COMPRESSION_XZ => "application/x-xz",
        }.freeze

        MIME_TYPE_TO_COMPRESSION = {
          "application/octet-stream" => COMPRESSION_NONE,
          "application/x-gzip" => COMPRESSION_GZIP,
          "application/x-bzip2" => COMPRESSION_BZIP2,
          "application/x-lzma" => COMPRESSION_LZMA,
          "application/x-xz" => COMPRESSION_XZ,
        }.freeze

        # File types (in TOC XML)
        TYPE_FILE      = "file"
        TYPE_DIRECTORY = "directory"
        TYPE_SYMLINK   = "symlink"
        TYPE_HARDLINK  = "hardlink"
        TYPE_FIFO      = "fifo"
        TYPE_BLOCK     = "block"
        TYPE_CHAR      = "character"
        TYPE_SOCKET    = "socket"

        # Header field offsets
        HEADER_MAGIC_OFFSET              = 0
        HEADER_SIZE_OFFSET               = 4
        HEADER_VERSION_OFFSET            = 6
        HEADER_TOC_COMPRESSED_OFFSET     = 8
        HEADER_TOC_UNCOMPRESSED_OFFSET   = 16
        HEADER_CKSUM_ALG_OFFSET          = 24

        # Default options for XAR archives
        DEFAULT_COMPRESSION     = COMPRESSION_GZIP
        DEFAULT_TOC_CHECKSUM    = "sha1"
        DEFAULT_FILE_CHECKSUM   = "sha1"
        DEFAULT_COMPRESSION_LEVEL = 6

        # TOC XML namespaces
        TOC_XML_DECLARATION = '<?xml version="1.0" encoding="UTF-8"?>'

        # Maximum path length
        MAX_PATH_LENGTH = 1024
      end
    end
  end
end

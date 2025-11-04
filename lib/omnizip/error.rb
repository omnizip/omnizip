# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

module Omnizip
  # Base error class for all Omnizip errors
  class Error < StandardError
  end

  # Error raised when compression fails
  class CompressionError < Error
  end

  # Error raised when decompression fails
  class DecompressionError < Error
  end

  # Error raised when an algorithm is not found
  class AlgorithmNotFoundError < Error
  end

  # Error raised when an unknown algorithm is requested
  class UnknownAlgorithmError < Error
  end

  # Error raised when a format is not supported
  class UnsupportedFormatError < Error
  end

  # Error raised when format parsing fails
  class FormatError < Error
  end

  # Error raised when archive is invalid
  class InvalidArchiveError < Error
  end

  # Error raised when I/O operations fail
  class IOError < Error
  end

  # Error raised when checksum validation fails
  class ChecksumError < Error
  end

  # Error raised when optimization strategy is not found
  class OptimizationNotFound < Error
  end

  # Error raised when progress tracking fails
  class ProgressError < Error
  end

  # Error raised when ETA calculation fails
  class ETAError < Error
  end

  # Error raised when RAR write is attempted without license
  class NotLicensedError < Error
    def initialize(message = default_message)
      super(message)
    end

    private

    def default_message
      <<~MSG
        RAR creation requires a licensed copy of WinRAR.

        To use RAR creation:
        1. Purchase a WinRAR license from https://www.rarlab.com/
        2. Install WinRAR on your system
        3. Confirm license ownership when prompted

        Alternatively, use 7z format which provides similar compression
        with no licensing restrictions:

          Omnizip::Formats::SevenZip.create('archive.7z') do |sz|
            sz.add_directory('files/')
          end
      MSG
    end
  end

  # Error raised when RAR executable is not found
  class RarNotAvailableError < Error
    def initialize(message = default_message)
      super(message)
    end

    private

    def default_message
      <<~MSG
        WinRAR executable not found.

        Please install WinRAR:
        - Windows: Download from https://www.rarlab.com/
        - Linux: Install 'rar' package (requires license)
        - macOS: Install via Homebrew: brew install rar (requires license)

        After installation, ensure 'rar' or 'Rar.exe' is in your PATH.
      MSG
    end
  end
end

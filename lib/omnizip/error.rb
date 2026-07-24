# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

module Omnizip
  class Error < StandardError
  end

  class CompressionError < Error
  end

  class DecompressionError < Error
  end

  class AlgorithmNotFoundError < Error
  end

  # Canonical alias of +AlgorithmNotFoundError+. Older code referenced
  # +UnknownAlgorithmError+; both names are kept for backward
  # compatibility.
  UnknownAlgorithmError = AlgorithmNotFoundError

  class UnknownChecksumError < Error
  end

  class UnknownFilterError < Error
  end

  class UnknownEncryptionStrategyError < Error
  end

  class ConversionNotSupportedError < Error
  end

  class UnsupportedFormatError < Error
  end

  class FormatError < Error
  end

  class InvalidArchiveError < Error
  end

  # Renamed from +IOError+ to avoid shadowing Ruby's built-in IOError.
  # The legacy name is kept as an alias.
  class IOOperationError < Error
  end
  IOError = IOOperationError

  class ChecksumError < Error
  end

  # Canonical name. +OptimizationNotFound+ kept as alias.
  class OptimizationNotFoundError < Error
  end
  OptimizationNotFound = OptimizationNotFoundError

  class ProgressError < Error
  end

  class ETAError < Error
  end

  class NotLicensedError < Error
    def initialize(message = default_message)
      super
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

  class RarNotAvailableError < Error
    def initialize(message = default_message)
      super
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

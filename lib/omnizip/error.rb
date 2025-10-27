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
end

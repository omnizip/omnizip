# frozen_string_literal: true

#
# Rubyzip Compatibility Layer
#
# This file provides a drop-in replacement for the 'zip' gem (rubyzip).
# Simply require 'omnizip/rubyzip_compat' instead of 'zip' to use Omnizip
# with existing rubyzip code.
#
# Usage:
#   require 'omnizip/rubyzip_compat'
#
#   Zip::File.open('archive.zip') do |zip|
#     zip.each { |entry| puts entry.name }
#   end
#

require_relative "../omnizip"

# Create Zip namespace as alias for Omnizip::Zip
module Zip
  # Rubyzip-compatible File class
  File = Omnizip::Zip::File

  # Rubyzip-compatible Entry class
  Entry = Omnizip::Zip::Entry

  # Rubyzip-compatible OutputStream class
  OutputStream = Omnizip::Zip::OutputStream

  # Rubyzip-compatible InputStream class
  InputStream = Omnizip::Zip::InputStream

  # Error classes for compatibility
  Error = Omnizip::Error
  FormatError = Omnizip::FormatError
  CompressionError = Omnizip::CompressionError
  DecompressionError = Omnizip::DecompressionError
  ChecksumError = Omnizip::ChecksumError

  # Version information
  VERSION = Omnizip::VERSION

  class << self
    # Legacy compatibility method
    # @deprecated Use Zip::File.open instead
    def open(*args, &block)
      File.open(*args, &block)
    end

    # Legacy compatibility method
    # @deprecated Use Zip::File.create instead
    def create(*args, &block)
      File.create(*args, &block)
    end
  end
end

# Compatibility note
if $VERBOSE
  warn "Omnizip: Using Omnizip rubyzip compatibility layer. " \
       "API is compatible with rubyzip, but implementation differs."
end
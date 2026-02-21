# frozen_string_literal: true

module Omnizip
  # Rubyzip-compatible API module
  #
  # Provides a Rubyzip-compatible interface for working with ZIP archives.
  # This allows existing code that uses Rubyzip to work with Omnizip.
  module Zip
    autoload :Entry, "omnizip/zip/entry"
    autoload :File, "omnizip/zip/file"
    autoload :OutputStream, "omnizip/zip/output_stream"
    autoload :InputStream, "omnizip/zip/input_stream"
  end
end

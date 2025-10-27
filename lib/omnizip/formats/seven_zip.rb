# frozen_string_literal: true

require_relative "seven_zip/constants"
require_relative "seven_zip/header"
require_relative "seven_zip/parser"
require_relative "seven_zip/reader"
require_relative "seven_zip/writer"
require_relative "seven_zip/coder_chain"
require_relative "seven_zip/stream_decompressor"
require_relative "seven_zip/stream_compressor"
require_relative "seven_zip/file_collector"
require_relative "seven_zip/header_writer"

module Omnizip
  module Formats
    # .7z archive format support
    # Provides read-only access to 7-Zip archives
    #
    # This module implements the .7z archive format specification,
    # supporting:
    # - Format signature and header validation
    # - Archive structure parsing
    # - File listing (Phase 2 - basic implementation)
    # - Future: File extraction (Phase 3)
    module SevenZip
      # Auto-register .7z format when loaded
      def self.register!
        require_relative "../format_registry"
        FormatRegistry.register(".7z", Reader)
      end
    end
  end
end

# Auto-register on load
Omnizip::Formats::SevenZip.register!

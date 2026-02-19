# frozen_string_literal: true

module Omnizip
  module FileType
    # Centralized MIME type classification for file type detection
    #
    # This class provides methods to classify MIME types into categories
    # and determine appropriate compression profiles based on file type.
    class MimeClassifier
      # Text-based MIME types
      TEXT_TYPES = %w[
        text/plain
        text/html
        text/css
        text/javascript
        text/xml
        text/csv
        text/markdown
        application/json
        application/xml
        application/javascript
        application/ecmascript
        application/x-httpd-php
        application/x-sh
        application/x-csh
        application/x-perl
        application/x-python
        application/x-ruby
        application/x-sql
        application/sql
      ].freeze

      # Archive MIME types
      ARCHIVE_TYPES = %w[
        application/zip
        application/x-7z-compressed
        application/x-rar-compressed
        application/x-tar
        application/gzip
        application/x-gzip
        application/x-bzip2
        application/x-xz
        application/x-lzip
        application/x-lzma
        application/x-compress
        application/zstd
        application/x-archive
        application/x-iso9660-image
      ].freeze

      # Executable MIME types
      EXECUTABLE_TYPES = %w[
        application/x-executable
        application/x-mach-binary
        application/x-elf
        application/x-sharedlib
        application/x-msdownload
        application/x-dosexec
        application/vnd.microsoft.portable-executable
      ].freeze

      # Binary/unknown MIME types (treated as binary data)
      BINARY_TYPES = %w[
        application/octet-stream
      ].freeze

      # Media MIME types (images, audio, video)
      MEDIA_TYPES = [
        /\Aimage\//,
        /\Aaudio\//,
        /\Avideo\//,
        "application/pdf",
      ].freeze

      class << self
        # Check if the MIME type is text-based
        #
        # @param mime_type [String] The MIME type to check
        # @return [Boolean] true if text-based
        def text?(mime_type)
          return false unless mime_type

          TEXT_TYPES.include?(mime_type) || mime_type.start_with?("text/")
        end

        # Check if the MIME type is an archive
        #
        # @param mime_type [String] The MIME type to check
        # @return [Boolean] true if archive
        def archive?(mime_type)
          return false unless mime_type

          ARCHIVE_TYPES.include?(mime_type)
        end

        # Check if the MIME type is executable
        #
        # @param mime_type [String] The MIME type to check
        # @return [Boolean] true if executable
        def executable?(mime_type)
          return false unless mime_type

          EXECUTABLE_TYPES.include?(mime_type) || BINARY_TYPES.include?(mime_type)
        end

        # Check if the MIME type is media (image/audio/video)
        #
        # @param mime_type [String] The MIME type to check
        # @return [Boolean] true if media
        def media?(mime_type)
          return false unless mime_type

          MEDIA_TYPES.any? do |pattern|
            case pattern
            when String
              mime_type == pattern
            when Regexp
              pattern.match?(mime_type)
            end
          end
        end

        # Determine the recommended profile category for a MIME type
        #
        # @param mime_type [String] The MIME type to classify
        # @return [Symbol] The recommended profile category
        #   (:text, :binary, :archive, :balanced)
        def profile_category(mime_type)
          return :balanced unless mime_type

          if text?(mime_type)
            :text
          elsif executable?(mime_type)
            :binary
          elsif archive?(mime_type) || media?(mime_type)
            :archive
          else
            :balanced
          end
        end
      end
    end
  end
end

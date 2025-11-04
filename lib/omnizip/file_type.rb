# frozen_string_literal: true

require "marcel"
require_relative "file_type/mime_classifier"

module Omnizip
  # File type detection module using Marcel for MIME type detection
  #
  # Provides MIME type detection using the Marcel library:
  # - Path-based detection (examines file extension and content)
  # - Data-based detection (analyzes binary data)
  # - Stream-based detection (reads from IO streams)
  #
  # @example Detect file type from path
  #   mime_type = Omnizip::FileType.detect('app.exe')
  #   # => 'application/x-executable'
  #
  # @example Detect from binary data
  #   mime_type = Omnizip::FileType.detect_data(File.binread('image.png'))
  #   # => 'image/png'
  #
  # @example Detect from IO stream with filename hint
  #   File.open('document.pdf', 'rb') do |file|
  #     mime_type = Omnizip::FileType.detect_stream(file, filename: 'document.pdf')
  #     # => 'application/pdf'
  #   end
  module FileType
    class << self
      # Detect MIME type from file path
      #
      # Uses Marcel to detect the MIME type by examining both the file
      # extension and file content. This is the most accurate detection
      # method when you have a file path.
      #
      # @param path [String, Pathname] File path
      # @return [String, nil] MIME type string or nil if detection fails
      #
      # @example
      #   FileType.detect('document.pdf')
      #   # => 'application/pdf'
      def detect(path)
        return nil unless path
        return nil unless File.exist?(path)

        Marcel::MimeType.for(Pathname.new(path))
      rescue StandardError
        nil
      end

      # Detect MIME type from binary data
      #
      # Uses Marcel to analyze binary data for MIME type detection.
      # Optionally accepts a filename hint for better accuracy.
      #
      # @param data [String] Binary data
      # @param filename [String, nil] Optional filename hint
      # @return [String, nil] MIME type string or nil if detection fails
      #
      # @example Without filename hint
      #   data = File.binread('image.png')
      #   FileType.detect_data(data)
      #   # => 'image/png'
      #
      # @example With filename hint
      #   FileType.detect_data(data, filename: 'image.png')
      #   # => 'image/png'
      def detect_data(data, filename: nil)
        return nil unless data
        return nil if data.empty?

        io = StringIO.new(data)
        io.set_encoding(Encoding::BINARY)

        Marcel::MimeType.for(io, name: filename)
      rescue StandardError
        nil
      end

      # Detect MIME type from IO stream
      #
      # Uses Marcel to analyze an IO stream for MIME type detection.
      # Optionally accepts a filename hint for better accuracy.
      # The stream position is preserved.
      #
      # @param io [IO] IO stream
      # @param filename [String, nil] Optional filename hint
      # @return [String, nil] MIME type string or nil if detection fails
      #
      # @example
      #   File.open('document.pdf', 'rb') do |file|
      #     FileType.detect_stream(file, filename: 'document.pdf')
      #     # => 'application/pdf'
      #   end
      def detect_stream(io, filename: nil)
        return nil unless io

        # Save current position
        original_pos = io.pos if io.respond_to?(:pos)

        mime_type = Marcel::MimeType.for(io, name: filename)

        # Restore position
        io.seek(original_pos) if original_pos && io.respond_to?(:seek)

        mime_type
      rescue StandardError
        # Attempt to restore position even on error
        io.seek(original_pos) if original_pos && io.respond_to?(:seek)
        nil
      end
    end
  end
end
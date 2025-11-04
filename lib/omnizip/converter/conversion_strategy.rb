# frozen_string_literal: true

module Omnizip
  module Converter
    # Base class for archive format conversion strategies
    class ConversionStrategy
      attr_reader :source_path, :target_path, :options

      # Initialize conversion strategy
      # @param source_path [String] Source archive path
      # @param target_path [String] Target archive path
      # @param options [ConversionOptions] Conversion options
      def initialize(source_path, target_path, options)
        @source_path = source_path
        @target_path = target_path
        @options = options
        @warnings = []
      end

      # Perform the conversion
      # @return [ConversionResult] Conversion result
      # @raise [NotImplementedError] Subclasses must implement
      def convert
        raise NotImplementedError, "#{self.class} must implement #convert"
      end

      # Get source format
      # @return [Symbol] Source format
      # @raise [NotImplementedError] Subclasses must implement
      def source_format
        raise NotImplementedError, "#{self.class} must implement #source_format"
      end

      # Get target format
      # @return [Symbol] Target format
      # @raise [NotImplementedError] Subclasses must implement
      def target_format
        raise NotImplementedError, "#{self.class} must implement #target_format"
      end

      # Check if this strategy can handle the conversion
      # @param source [String] Source file path
      # @param target [String] Target file path
      # @return [Boolean] True if can handle
      def self.can_convert?(source, target)
        false
      end

      protected

      # Add a warning message
      # @param message [String] Warning message
      def add_warning(message)
        @warnings << message
      end

      # Get all warnings
      # @return [Array<String>] List of warnings
      def warnings
        @warnings
      end

      # Detect format from file extension
      # @param path [String] File path
      # @return [Symbol] Format
      def detect_format(path)
        ext = File.extname(path).downcase
        case ext
        when ".zip"
          :zip
        when ".7z"
          :seven_zip
        else
          raise ArgumentError, "Unknown format for file: #{path}"
        end
      end

      # Create conversion result
      # @param start_time [Time] Start time
      # @param entry_count [Integer] Number of entries
      # @return [ConversionResult] Result object
      def create_result(start_time, entry_count)
        require_relative "../models/conversion_result"

        duration = Time.now - start_time
        source_size = File.size(source_path)
        target_size = File.size(target_path)

        Omnizip::Models::ConversionResult.new(
          source_path: source_path,
          target_path: target_path,
          source_format: source_format,
          target_format: target_format,
          source_size: source_size,
          target_size: target_size,
          duration: duration,
          entry_count: entry_count,
          warnings: warnings
        )
      end

      # Check if metadata is compatible between formats
      # @param entry [Entry] Entry to check
      # @return [Boolean] True if fully compatible
      def metadata_compatible?(entry)
        # ZIP supports most metadata
        # 7z has limited metadata support
        case [source_format, target_format]
        when [:zip, :seven_zip]
          # Some metadata loss (comments, extra fields)
          false
        when [:seven_zip, :zip]
          # Can preserve most 7z metadata in ZIP
          true
        else
          true
        end
      end
    end
  end
end
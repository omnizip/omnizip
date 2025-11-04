# frozen_string_literal: true

module Omnizip
  module Models
    # Model for format conversion results
    class ConversionResult
      attr_reader :source_path, :target_path, :source_format, :target_format,
                  :source_size, :target_size, :duration, :entry_count,
                  :compression_ratio, :warnings

      # Initialize conversion result
      # @param source_path [String] Source file path
      # @param target_path [String] Target file path
      # @param source_format [Symbol] Source format
      # @param target_format [Symbol] Target format
      # @param source_size [Integer] Source file size in bytes
      # @param target_size [Integer] Target file size in bytes
      # @param duration [Float] Conversion duration in seconds
      # @param entry_count [Integer] Number of entries converted
      # @param warnings [Array<String>] Conversion warnings
      def initialize(
        source_path:,
        target_path:,
        source_format:,
        target_format:,
        source_size:,
        target_size:,
        duration:,
        entry_count:,
        warnings: []
      )
        @source_path = source_path
        @target_path = target_path
        @source_format = source_format
        @target_format = target_format
        @source_size = source_size
        @target_size = target_size
        @duration = duration
        @entry_count = entry_count
        @warnings = warnings
        @compression_ratio = calculate_compression_ratio
      end

      # Get size reduction percentage
      # @return [Float] Size reduction as percentage
      def size_reduction
        return 0.0 if source_size.zero?

        ((source_size - target_size).to_f / source_size * 100).round(2)
      end

      # Get size ratio
      # @return [Float] Target size as percentage of source size
      def size_ratio
        return 0.0 if source_size.zero?

        (target_size.to_f / source_size * 100).round(2)
      end

      # Check if conversion resulted in smaller file
      # @return [Boolean] True if target is smaller
      def smaller?
        target_size < source_size
      end

      # Check if conversion resulted in larger file
      # @return [Boolean] True if target is larger
      def larger?
        target_size > source_size
      end

      # Check if there were warnings
      # @return [Boolean] True if warnings exist
      def warnings?
        !warnings.empty?
      end

      # Get average processing speed
      # @return [Float] MB/s processing speed
      def processing_speed
        return 0.0 if duration.zero?

        (source_size / duration / 1_048_576.0).round(2)
      end

      # Convert to hash
      # @return [Hash] Result as hash
      def to_h
        {
          source_path: source_path,
          target_path: target_path,
          source_format: source_format,
          target_format: target_format,
          source_size: source_size,
          target_size: target_size,
          size_reduction: size_reduction,
          size_ratio: size_ratio,
          duration: duration,
          entry_count: entry_count,
          processing_speed: processing_speed,
          warnings: warnings
        }
      end

      # Format as human-readable string
      # @return [String] Formatted result
      def to_s
        "Converted #{source_path} (#{format_size(source_size)}) to " \
        "#{target_path} (#{format_size(target_size)}) in #{duration.round(2)}s. " \
        "#{size_reduction > 0 ? "Saved #{size_reduction}%" : "Increased #{-size_reduction}%"}"
      end

      private

      def calculate_compression_ratio
        return 0.0 if source_size.zero?

        (1.0 - (target_size.to_f / source_size)).round(4)
      end

      def format_size(bytes)
        return "0 B" if bytes.zero?

        units = %w[B KB MB GB TB]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = [exp, units.size - 1].min

        "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
      end
    end
  end
end
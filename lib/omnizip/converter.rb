# frozen_string_literal: true

require_relative "models/conversion_options"
require_relative "models/conversion_result"
require_relative "converter/conversion_strategy"
require_relative "converter/zip_to_seven_zip_strategy"
require_relative "converter/seven_zip_to_zip_strategy"
require_relative "converter/conversion_registry"

module Omnizip
  # Archive format conversion module
  # Provides conversion between different archive formats
  module Converter
    class << self
      # Convert archive from one format to another
      # @param source_path [String] Source archive path
      # @param target_path [String] Target archive path
      # @param options [Hash, ConversionOptions] Conversion options
      # @return [ConversionResult] Conversion result
      def convert(source_path, target_path, **options)
        # Validate input files
        unless File.exist?(source_path)
          raise Errno::ENOENT, "Source file not found: #{source_path}"
        end

        # Create options object
        opts = options.is_a?(Models::ConversionOptions) ? options : create_options(**options)
        opts.validate

        # Find appropriate strategy
        strategy_class = ConversionRegistry.find_strategy(source_path, target_path)
        unless strategy_class
          raise ArgumentError, "No conversion strategy available for " \
                              "#{source_path} -> #{target_path}"
        end

        # Perform conversion
        strategy = strategy_class.new(source_path, target_path, opts)
        result = strategy.convert

        # Delete source if requested
        File.delete(source_path) if opts.delete_source && File.exist?(source_path)

        result
      end

      # Convert with explicit options object
      # @param source_path [String] Source archive path
      # @param target_path [String] Target archive path
      # @param options [ConversionOptions] Conversion options
      # @return [ConversionResult] Conversion result
      def convert_with_options(source_path, target_path, options)
        convert(source_path, target_path, options)
      end

      # Check if conversion is supported
      # @param source_path [String] Source archive path
      # @param target_path [String] Target archive path
      # @return [Boolean] True if conversion is supported
      def supported?(source_path, target_path)
        ConversionRegistry.supported?(source_path, target_path)
      end

      # Get available conversion strategies
      # @return [Array<Class>] List of strategy classes
      def strategies
        ConversionRegistry.strategies
      end

      # Batch convert multiple archives
      # @param sources [Array<String>] Source file paths
      # @param target_format [Symbol] Target format (:zip or :seven_zip)
      # @param options [Hash] Conversion options
      # @yield [result] Optional block called for each conversion
      # @return [Array<ConversionResult>] Conversion results
      def batch_convert(sources, target_format: :seven_zip, **options, &block)
        results = []

        sources.each do |source|
          target = generate_target_path(source, target_format)
          result = convert(source, target, target_format: target_format, **options)
          results << result
          block.call(result) if block_given?
        end

        results
      end

      private

      def create_options(**options)
        Models::ConversionOptions.new(**options)
      end

      def generate_target_path(source, target_format)
        base = File.basename(source, File.extname(source))
        dir = File.dirname(source)
        ext = target_format == :seven_zip ? ".7z" : ".zip"
        File.join(dir, base + ext)
      end
    end
  end
end
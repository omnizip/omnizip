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
      def self.can_convert?(_source, _target)
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

      # Repack the extracted tree under +extracted_dir+ into a new
      # archive at +target_path+ through the Archive facade (the
      # format is resolved from the target's extension). Directory
      # entries are implied by file paths, matching every strategy's
      # treatment. Returns the number of file entries written.
      #
      # @param extracted_dir [String] Directory of extracted entries
      # @param write_options [Hash] Format writer options
      # @return [Integer] Number of file entries written
      def repack_tree(extracted_dir, **write_options)
        count = 0
        Omnizip::Archive.create(target_path, **write_options) do |archive|
          Dir.glob(File.join(extracted_dir, "**", "*")).each do |path|
            next if File.directory?(path)

            archive.add_file(path, path.delete_prefix("#{extracted_dir}/"))
            count += 1
          end
        end
        count
      end

      # Create conversion result
      # @param start_time [Time] Start time
      # @param entry_count [Integer] Number of entries
      # @return [ConversionResult] Result object
      def create_result(start_time, entry_count)
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
          warnings: warnings,
        )
      end
    end
  end
end

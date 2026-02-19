# frozen_string_literal: true

require_relative "conversion_strategy"

module Omnizip
  module Converter
    # Convert ZIP archives to 7-Zip format
    class ZipToSevenZipStrategy < ConversionStrategy
      # Perform ZIP to 7z conversion
      # @return [ConversionResult] Conversion result
      def convert
        start_time = Time.now
        entry_count = 0

        require_relative "../zip/file"
        require_relative "../formats/seven_zip"

        # Open source ZIP archive
        Omnizip::Zip::File.open(source_path) do |zip|
          # Collect all entries and their data
          entries_data = collect_entries(zip)
          entry_count = entries_data.size

          # Create target 7z archive
          create_seven_zip(entries_data)
        end

        create_result(start_time, entry_count)
      end

      # Get source format
      # @return [Symbol] Source format (:zip)
      def source_format
        :zip
      end

      # Get target format
      # @return [Symbol] Target format (:seven_zip)
      def target_format
        :seven_zip
      end

      # Check if can convert
      # @param source [String] Source file
      # @param target [String] Target file
      # @return [Boolean] True if can convert
      def self.can_convert?(source, target)
        source.end_with?(".zip") && target.end_with?(".7z")
      end

      private

      def collect_entries(zip)
        entries = []

        zip.entries.each do |entry|
          data = {
            name: entry.name,
            directory: entry.directory?,
            mtime: entry.time,
            content: nil,
          }

          unless entry.directory?
            data[:content] = zip.get_input_stream(entry)

            if options.preserve_metadata && entry.unix_perms.positive?
              data[:unix_perms] = entry.unix_perms
            end
          end

          entries << data
        end

        entries
      end

      def create_seven_zip(entries)
        writer = Omnizip::Formats::SevenZip::Writer.new(target_path)

        # Set compression options
        compression = options.compression || :lzma2
        level = options.compression_level || 5
        options.solid.nil? || options.solid

        # Add each entry
        entries.each do |entry_data|
          if entry_data[:directory]
            # 7z doesn't have explicit directory entries
            # Directories are implied by file paths
            next
          end

          writer.add_data(
            entry_data[:name],
            entry_data[:content],
            algorithm: compression,
            level: level,
          )
        end

        # Apply filter if specified
        if options.filter
          add_warning("Filters not yet supported in 7z conversion")
        end

        # Write the archive
        writer.write
      end
    end
  end
end

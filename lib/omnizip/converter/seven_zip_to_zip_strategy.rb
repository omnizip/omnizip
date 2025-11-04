# frozen_string_literal: true

require_relative "conversion_strategy"

module Omnizip
  module Converter
    # Convert 7-Zip archives to ZIP format
    class SevenZipToZipStrategy < ConversionStrategy
      # Perform 7z to ZIP conversion
      # @return [ConversionResult] Conversion result
      def convert
        start_time = Time.now
        entry_count = 0

        require_relative "../formats/seven_zip"
        require_relative "../zip/file"

        # Open source 7z archive
        reader = Omnizip::Formats::SevenZip::Reader.new(source_path)
        reader.read

        # Collect entries
        entries_data = collect_seven_zip_entries(reader)
        entry_count = entries_data.size

        # Create target ZIP archive
        create_zip(entries_data)

        create_result(start_time, entry_count)
      end

      # Get source format
      # @return [Symbol] Source format (:seven_zip)
      def source_format
        :seven_zip
      end

      # Get target format
      # @return [Symbol] Target format (:zip)
      def target_format
        :zip
      end

      # Check if can convert
      # @param source [String] Source file
      # @param target [String] Target file
      # @return [Boolean] True if can convert
      def self.can_convert?(source, target)
        source.end_with?(".7z") && target.end_with?(".zip")
      end

      private

      def collect_seven_zip_entries(reader)
        entries = []

        reader.entries.each do |entry|
          data = {
            name: entry.name,
            content: nil,
            mtime: entry.mtime || Time.now
          }

          # Extract entry data
          unless entry.name.end_with?("/")
            File.open(source_path, "rb") do |io|
              data[:content] = reader.send(:extract_entry_data, io, entry)
            end
          end

          entries << data
        end

        entries
      end

      def create_zip(entries)
        Omnizip::Zip::File.create(target_path) do |zip|
          entries.each do |entry_data|
            if entry_data[:name].end_with?("/")
              # Directory entry
              zip.add(entry_data[:name])
            else
              # File entry
              zip.add(entry_data[:name]) { entry_data[:content] }
            end
          end

          # Set archive comment if preserving metadata
          if options.preserve_metadata
            zip.comment = "Converted from 7z by Omnizip"
          end
        end
      end
    end
  end
end
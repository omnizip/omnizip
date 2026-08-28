# frozen_string_literal: true

require "tmpdir"

module Omnizip
  module Converter
    # Convert 7-Zip archives to ZIP format
    class SevenZipToZipStrategy < ConversionStrategy
      # Perform 7z to ZIP conversion
      # @return [ConversionResult] Conversion result
      def convert
        start_time = Time.now

        reader = Omnizip::Formats::SevenZip::Reader.new(source_path)
        reader.open
        entry_count = reader.list_files.size

        Dir.mktmpdir("omnizip_convert") do |tmp|
          reader.extract_all(tmp)

          writer = Omnizip::Formats::Zip::Writer.new(target_path)
          Dir.glob(File.join(tmp, "**", "*")).each do |path|
            next if File.directory?(path)

            writer.add_file(path, path.delete_prefix("#{tmp}/"))
          end
          writer.write
        end

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
    end
  end
end

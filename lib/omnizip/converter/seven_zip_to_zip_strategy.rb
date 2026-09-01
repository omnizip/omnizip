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

        entry_count = Dir.mktmpdir("omnizip_convert") do |tmp|
          Omnizip.extract_archive(source_path, tmp)
          repack_tree(tmp)
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

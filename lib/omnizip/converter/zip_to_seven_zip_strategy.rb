# frozen_string_literal: true

require "tmpdir"

module Omnizip
  module Converter
    # Convert ZIP archives to 7-Zip format
    class ZipToSevenZipStrategy < ConversionStrategy
      # Perform ZIP to 7z conversion
      # @return [ConversionResult] Conversion result
      def convert
        start_time = Time.now
        entry_count = 0

        Dir.mktmpdir("omnizip_convert_zip") do |tmp|
          # Extract the ZIP through the native reader; directories are
          # implied by extracted file paths
          Omnizip::Formats::Zip.extract(source_path, tmp)

          writer = Omnizip::Formats::SevenZip::Writer.new(target_path,
                                                          writer_options)
          Dir.glob(File.join(tmp, "**", "*")).each do |path|
            next if File.directory?(path)

            entry_count += 1
            writer.add_file(path, path.delete_prefix("#{tmp}/"))
          end
          writer.write
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

      # SevenZip::Writer takes algorithm/level/solid as keywords
      def writer_options
        {
          algorithm: options.compression || :lzma2,
          level: options.compression_level || 5,
        }
      end
    end
  end
end

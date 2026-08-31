# frozen_string: true

require "tmpdir"

module Omnizip
  module Converter
    # Fallback conversion strategy: extract any routed source format
    # and repack the tree into any writable target format, both
    # through the handler registry. Registered after the direct
    # entry-copy strategies, which keep precedence for their pairs.
    class ExtractRepackStrategy < ConversionStrategy
      WRITABLE_FORMATS = %i[zip seven_zip tar rar].freeze

      # Any routed source extension converts to any writable target
      def self.can_convert?(source, _target)
        !source_format_for(source).nil? &&
          WRITABLE_FORMATS.include?(target_format_for(_target))
      end

      # Routed read-side format for an extension, or nil
      def self.source_format_for(path)
        ext = File.extname(path).downcase
        Convenience::ARCHIVE_FORMAT_EXTENSIONS[ext] ||
          Convenience::READ_ARCHIVE_FORMAT_EXTENSIONS[ext]
      end

      # Writable format for a target extension, or nil
      def self.target_format_for(path)
        Convenience::ARCHIVE_FORMAT_EXTENSIONS[File.extname(path).downcase]
      end

      def convert
        start_time = Time.now

        Dir.mktmpdir("omnizip_convert_repack") do |tmp|
          extracted = Omnizip.extract_archive(source_path, tmp)

          Omnizip::Archive.create(target_path,
                                  format: self.class.target_format_for(target_path)) do |b|
            Dir.glob(File.join(tmp, "**", "*")).each do |path|
              next if File.directory?(path)

              b.add_file(path, path.delete_prefix("#{tmp}/"))
            end
          end

          entry_count = extracted.size
          create_result(start_time, entry_count)
        end
      end

      def source_format
        self.class.source_format_for(source_path) || :unknown
      end

      def target_format
        self.class.target_format_for(target_path) || :unknown
      end
    end
  end
end

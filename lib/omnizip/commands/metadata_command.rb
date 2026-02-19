# frozen_string_literal: true

require_relative "../cli/output_formatter"

module Omnizip
  module Commands
    # Metadata command implementation
    class MetadataCommand
      attr_reader :options

      def initialize(options = {})
        @options = options
      end

      # Run the metadata command
      # @param archive_path [String] Path to archive
      # @param pattern [String, nil] Optional pattern to match entries
      def run(archive_path, pattern = nil)
        require_relative "../zip/file"
        require_relative "../metadata"

        unless File.exist?(archive_path)
          raise Errno::ENOENT, "Archive not found: #{archive_path}"
        end

        Omnizip::Zip::File.open(archive_path) do |archive|
          if options[:show]
            show_metadata(archive, pattern)
          else
            edit_metadata(archive, pattern)
          end
        end

        puts "Metadata updated successfully" unless options[:show]
      end

      private

      def show_metadata(archive, pattern)
        if pattern
          # Show entry metadata
          entry = archive.get_entry(pattern)
          unless entry
            warn "Entry not found: #{pattern}"
            return
          end

          show_entry_metadata(entry)
        else
          # Show archive metadata
          show_archive_metadata(archive)
        end
      end

      def show_archive_metadata(archive)
        metadata = archive.metadata
        puts "Archive: #{archive.name}"
        puts "Comment: #{metadata.comment}" unless metadata.comment.empty?
        puts "Created: #{metadata.created_at}" if metadata.created_at
        puts "Modified: #{metadata.modified_at}" if metadata.modified_at
        puts "Entries: #{metadata.entry_count} (#{metadata.file_count} files, #{metadata.directory_count} dirs)"
        puts "Total size: #{format_size(metadata.total_size)}"
        puts "Compressed: #{format_size(metadata.total_compressed_size)}"
        puts "Ratio: #{(metadata.compression_ratio * 100).round(1)}%"
      end

      def show_entry_metadata(entry)
        metadata = entry.metadata
        puts "Entry: #{entry.name}"
        puts "Comment: #{metadata.comment}" unless metadata.comment.empty?
        puts "Modified: #{metadata.mtime}"
        puts "Permissions: 0#{metadata.unix_permissions.to_s(8)}"
        puts "Size: #{format_size(entry.size)}"
        puts "Compressed: #{format_size(entry.compressed_size)}"
        puts "CRC32: 0x#{entry.crc.to_s(16).upcase}"
        puts "Type: #{entry.directory? ? 'Directory' : 'File'}"
      end

      def edit_metadata(archive, pattern)
        if pattern
          edit_entry_metadata(archive, pattern)
        else
          edit_archive_metadata(archive)
        end

        archive.save_metadata
      end

      def edit_archive_metadata(archive)
        metadata = archive.metadata

        if options[:comment]
          metadata.comment = options[:comment]
        end
      end

      def edit_entry_metadata(archive, pattern)
        entries = if pattern.include?("*") || pattern.include?("?")
                    # Glob pattern
                    archive.entries.select { |e| File.fnmatch(pattern, e.name) }
                  else
                    # Single entry
                    [archive.get_entry(pattern)].compact
                  end

        if entries.empty?
          warn "No entries match pattern: #{pattern}"
          return
        end

        entries.each do |entry|
          metadata = entry.metadata

          metadata.comment = options[:comment] if options[:comment]
          metadata.mtime = parse_time(options[:set_mtime]) if options[:set_mtime]
          metadata.unix_permissions = parse_permissions(options[:chmod]) if options[:chmod]
          metadata.attributes = options[:set_attribute].to_sym if options[:set_attribute]

          entry.save_metadata
        end

        puts "Updated #{entries.size} #{entries.size == 1 ? 'entry' : 'entries'}" if options[:verbose]
      end

      def parse_time(time_str)
        return Time.now if time_str == "now"

        Time.parse(time_str)
      rescue ArgumentError => e
        raise ArgumentError, "Invalid time format: #{time_str} (#{e.message})"
      end

      def parse_permissions(perms_str)
        # Handle octal (755) or decimal
        if perms_str.start_with?("0")
          perms_str.to_i(8)
        else
          perms_str.to_i
        end
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

# frozen_string: true

require "fileutils"
require "tmpdir"

module Omnizip
  module Formats
    module Rar5
      # RAR v5 archive writer
      #
      # @example Writing a RAR5 archive
      #   writer = Rar5::Writer.new
      #   File.open("archive.rar", "wb") do |file|
      #     entries = [
      #       {name: "file.txt", data: "content", time: Time.now}
      #     ]
      #     writer.write_archive(file, entries)
      #   end
      class Writer < Omnizip::Formats::Rar::RarFormatBase
        # Initialize a RAR v5 writer
        def initialize
          super("rar5")
        end

        # Write a RAR v5 archive
        #
        # Delegates to the primary `Formats::Rar::Rar5::Writer` so the
        # output is spec-conformant and unrar-verified: entries spill
        # to a temporary file, the primary writer produces the
        # archive, and the bytes are copied into the given IO.
        # Compression methods above :store are not official-RAR
        # compatible, so the primary writer stores them (with a
        # warning) rather than emitting an undecodable stream.
        #
        # @param io [IO] The output stream
        # @param entries [Array<Hash>] The entries to write
        # @return [void]
        def write_archive(io, entries)
          Dir.mktmpdir("omnizip_rar5_write") do |tmp|
            archive_path = File.join(tmp, "archive.rar")
            primary = Rar::Rar5::Writer.new(archive_path,
                                            include_mtime: true,
                                            include_crc32: true)

            entries.each do |entry|
              name = entry[:name] || entry["name"]
              data = entry[:data] || entry["data"]
              mtime = entry[:time] || entry["time"] || Time.now

              file_path = File.join(tmp, "entries", name)
              FileUtils.mkdir_p(File.dirname(file_path))
              File.binwrite(file_path, data.to_s)
              File.utime(mtime, mtime, file_path)

              primary.add_file(file_path, name)
            end

            primary.write
            io.write(File.binread(archive_path))
          end
        end
      end
    end
  end
end

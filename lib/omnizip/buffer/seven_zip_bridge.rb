# frozen_string_literal: true

require "stringio"
require "tmpdir"

module Omnizip
  module Buffer
    # Bridges the in-memory Buffer API onto the file-based 7z
    # reader/writer through a temporary file, since the 7z format has
    # no in-memory stream implementation.
    module SevenZipBridge
      class << self
        # Create a 7z archive in memory
        #
        # @param buffer [StringIO] Destination buffer
        # @param options [Hash] Writer options
        # @yield [WriteProxy] Block adding entries
        def create(buffer, options = {}, &block)
          Dir.mktmpdir("omnizip_buffer_7z") do |tmp|
            archive_path = File.join(tmp, "buffer.7z")
            writer = Formats::SevenZip::Writer.new(archive_path, options)
            block&.call(WriteProxy.new(writer))
            writer.write

            buffer.write(File.binread(archive_path))
          end
        end

        # Read a 7z archive from memory
        #
        # @param buffer [StringIO] Archive bytes
        # @yield [ReadProxy] Block reading entries
        # @return [ReadProxy, Object] Proxy or block result
        def open(buffer, &block)
          Dir.mktmpdir("omnizip_buffer_7z") do |tmp|
            archive_path = File.join(tmp, "buffer.7z")
            File.binwrite(archive_path, buffer.string)

            reader = Formats::SevenZip::Reader.new(archive_path)
            reader.open
            proxy = ReadProxy.new(reader, tmp)

            block ? yield(proxy) : proxy
          end
        end
      end

      # Mirrors the MemoryArchive write interface onto a 7z writer
      class WriteProxy
        # @param writer [Formats::SevenZip::Writer]
        def initialize(writer)
          @writer = writer
        end

        # Add an entry; a trailing slash with empty content adds a
        # directory entry
        #
        # @param name [String] Entry name
        # @param data [String] Entry content
        # @return [self]
        def add(name, data, **_options)
          if name.end_with?("/") && data.to_s.empty?
            @writer.add_directory_entry(name)
          else
            @writer.add_data(name, data)
          end
          self
        end
      end

      # Mirrors the MemoryArchive read interface onto a 7z reader
      class ReadProxy
        # @param reader [Formats::SevenZip::Reader] opened reader
        # @param tmp [String] Scratch directory for extraction
        def initialize(reader, tmp)
          @reader = reader
          @tmp = tmp
        end

        # Yield an Entry wrapper per archive entry
        def each_entry
          @reader.list_files.each do |entry|
            yield Entry.new(entry, @reader, @tmp)
          end
        end

        # Filename => content for every file entry
        #
        # @return [Hash<String, String>]
        def extract_all_to_memory
          result = {}
          each_entry do |entry|
            result[entry.name] = entry.read unless entry.directory?
          end
          result
        end

        # Entry names; directories keep a trailing slash like the ZIP
        # listing convention
        #
        # @return [Array<String>]
        def entry_names
          @reader.list_files.map do |entry|
            entry.is_dir ? "#{entry.name}/" : entry.name
          end
        end

        # Read-only access to the underlying entries
        #
        # @return [Array<Formats::SevenZip::Models::FileEntry>]
        def raw_entries
          @reader.list_files
        end

        # Entry wrapper matching MemoryArchive::Entry's surface
        class Entry
          attr_reader :name, :size

          # @param entry [Formats::SevenZip::Models::FileEntry]
          # @param reader [Formats::SevenZip::Reader]
          # @param tmp [String] Scratch directory
          def initialize(entry, reader, tmp)
            @entry = entry
            @reader = reader
            @tmp = tmp
            @name = if entry.is_dir
                      entry.name.end_with?("/") ? entry.name : "#{entry.name}/"
                    else
                      entry.name
                    end
            @size = entry.size
          end

          # @return [Boolean]
          def directory?
            @entry.is_dir
          end

          # @return [Time, nil]
          def time
            @entry.mtime
          end

          # Extract and return this entry's content
          #
          # @return [String]
          def read(_size = nil)
            return "" if directory? || @entry.has_stream == false

            dest = File.join(@tmp, "entry", @entry.name)
            @reader.extract_entry(@entry.name, dest)
            File.binread(dest)
          end
        end
      end
    end
  end
end

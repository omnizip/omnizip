# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Solid
          # Solid stream for concatenating multiple files
          #
          # In solid compression, multiple files are concatenated into a single
          # compression stream, allowing the compressor to use data from earlier
          # files as dictionary/context for later files. This significantly
          # improves compression ratios for similar files.
          #
          # The stream maintains file boundaries and metadata to enable proper
          # extraction while keeping all data in one continuous buffer.
          #
          # @example Create solid stream with multiple files
          #   stream = SolidStream.new
          #   stream.add_file('file1.txt', File.binread('file1.txt'))
          #   stream.add_file('file2.txt', File.binread('file2.txt'))
          #   data = stream.concatenated_data
          class SolidStream
            # @return [Array<Hash>] File entries with metadata
            attr_reader :files

            # @return [String] Concatenated file data
            attr_reader :concatenated_data

            # Initialize solid stream
            def initialize
              @files = []
              @concatenated_data = String.new(encoding: Encoding::BINARY)
              @current_offset = 0
            end

            # Add file to solid stream
            #
            # @param filename [String] File name for archive
            # @param data [String] File data (binary)
            # @param metadata [Hash] Additional file metadata
            # @option metadata [Time] :mtime Modification time
            # @option metadata [File::Stat] :stat File stat object
            # @return [void]
            def add_file(filename, data, metadata = {})
              # Store file information
              file_entry = {
                filename: filename,
                offset: @current_offset,
                size: data.bytesize,
                mtime: metadata[:mtime],
                stat: metadata[:stat],
              }

              @files << file_entry

              # Append data to stream
              @concatenated_data << data

              # Update offset
              @current_offset += data.bytesize
            end

            # Get total size of all files
            #
            # @return [Integer] Total size in bytes
            def total_size
              @concatenated_data.bytesize
            end

            # Get file count
            #
            # @return [Integer] Number of files
            def file_count
              @files.size
            end

            # Get file entry by index
            #
            # @param index [Integer] File index (0-based)
            # @return [Hash, nil] File entry or nil if not found
            def file_at(index)
              return nil if index.negative? || index >= @files.size

              @files[index]
            end

            # Extract file data by index
            #
            # @param index [Integer] File index (0-based)
            # @return [String, nil] File data or nil if not found
            def extract_file_data(index)
              return nil if index.negative? || index >= @files.size

              file = @files[index]
              return nil unless file

              @concatenated_data[file[:offset], file[:size]]
            end

            # Clear all data and reset
            #
            # @return [void]
            def clear
              @files.clear
              @concatenated_data.clear
              @current_offset = 0
            end

            # Check if stream is empty
            #
            # @return [Boolean] true if no files added
            def empty?
              @files.empty?
            end
          end
        end
      end
    end
  end
end

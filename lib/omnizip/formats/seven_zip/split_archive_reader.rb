# frozen_string_literal: true

require_relative "constants"
require_relative "header"
require_relative "parser"
require_relative "models/stream_info"
require_relative "models/file_entry"
require_relative "stream_decompressor"
require_relative "../../models/split_options"
require "fileutils"

module Omnizip
  module Formats
    module SevenZip
      # Split archive reader for .7z format
      # Reads multi-volume archives
      class SplitArchiveReader
        include Constants

        attr_reader :base_path, :header, :entries, :stream_info, :volumes

        # Initialize reader with base path
        #
        # @param base_path [String] Path to first volume (e.g., "backup.7z.001")
        def initialize(base_path)
          @base_path = base_path
          @entries = []
          @stream_info = nil
          @volumes = []
          @volume_handles = []
        end

        # Detect and open all volumes
        #
        # @raise [RuntimeError] if files cannot be opened or parsed
        def open
          detect_volumes
          open_volumes
          parse_archive
          self
        end

        # Check if archive is split
        #
        # @return [Boolean] true if split across multiple volumes
        def split?
          @volumes.size > 1
        end

        # Get total number of volumes
        #
        # @return [Integer] Number of volumes
        def total_volumes
          @volumes.size
        end

        # Get volume size (first volume)
        #
        # @return [Integer] Volume size in bytes
        def volume_size
          return 0 if @volumes.empty?

          File.size(@volumes.first)
        end

        # List all files in archive
        #
        # @return [Array<Models::FileEntry>] File entries
        def list_files
          @entries
        end

        # Extract file to output path
        #
        # @param entry_name [String] File name to extract
        # @param output_path [String] Destination path
        # @raise [RuntimeError] if entry not found or extraction fails
        def extract_entry(entry_name, output_path)
          entry = @entries.find { |e| e.name == entry_name }
          raise "Entry not found: #{entry_name}" unless entry

          # Create directory if needed
          FileUtils.mkdir_p(File.dirname(output_path))

          # Extract file
          if entry.directory?
            FileUtils.mkdir_p(output_path)
          elsif entry.has_stream?
            data = extract_entry_data(entry)
            File.binwrite(output_path, data)

            # Set timestamp if available
            if entry.mtime
              File.utime(entry.atime || entry.mtime || Time.now,
                         entry.mtime || Time.now,
                         output_path)
            end
          else
            # Empty file
            FileUtils.touch(output_path)
          end
        end

        # Extract all files to directory
        #
        # @param output_dir [String] Destination directory
        # @raise [RuntimeError] on extraction error
        def extract_all(output_dir)
          FileUtils.mkdir_p(output_dir)

          @entries.each do |entry|
            output_path = File.join(output_dir, entry.name)
            extract_entry(entry.name, output_path)
          end
        end

        # Check if archive is valid .7z format
        #
        # @return [Boolean] true if valid
        def valid?
          !@header.nil? && @header.valid?
        end

        # Close all volume handles
        def close
          @volume_handles.each(&:close)
          @volume_handles.clear
        end

        private

        # Detect all volumes in the set
        def detect_volumes
          @volumes = []

          # Determine naming pattern
          naming_pattern = detect_naming_pattern(@base_path)

          case naming_pattern
          when :numeric
            detect_numeric_volumes
          when :alpha
            detect_alpha_volumes
          else
            # Single volume
            @volumes = [@base_path]
          end
        end

        # Detect naming pattern from base path
        #
        # @param path [String] Base path
        # @return [Symbol] :numeric, :alpha, or :single
        def detect_naming_pattern(path)
          if /\.(\d{3})$/.match?(path)
            :numeric
          elsif /\.([a-z]{2,})$/.match?(path)
            :alpha
          else
            :single
          end
        end

        # Detect volumes with numeric naming (.001, .002, ...)
        def detect_numeric_volumes
          base = @base_path.sub(/\.\d{3}$/, "")
          volume_num = 1

          loop do
            volume_path = format("%s.%03d", base, volume_num)
            break unless File.exist?(volume_path)

            @volumes << volume_path
            volume_num += 1
          end

          raise "No volumes found for #{@base_path}" if @volumes.empty?
        end

        # Detect volumes with alpha naming (.aa, .ab, ...)
        def detect_alpha_volumes
          base = @base_path.sub(/\.[a-z]{2,}$/, "")
          volume_num = 1
          split_opts = Omnizip::Models::SplitOptions.new
          split_opts.naming_pattern = Omnizip::Models::SplitOptions::NAMING_ALPHA

          loop do
            volume_path = split_opts.volume_filename(base, volume_num)
            break unless File.exist?(volume_path)

            @volumes << volume_path
            volume_num += 1
          end

          raise "No volumes found for #{@base_path}" if @volumes.empty?
        end

        # Open all volume files
        def open_volumes
          @volume_handles = @volumes.map { |path| File.open(path, "rb") }
        end

        # Parse .7z archive structure across volumes
        def parse_archive
          # Read and validate start header from first volume
          @header = Header.read(@volume_handles.first)

          # Read next header metadata
          next_header_data = read_from_volumes(
            @header.start_pos_after_header + @header.next_header_offset,
            @header.next_header_size,
          )

          # Check if header is encoded (compressed or encrypted)
          # ENCODED_HEADER (0x17) can mean compressed or encrypted
          first_byte = next_header_data.getbyte(0)
          if first_byte == PropertyId::ENCODED_HEADER
            # Note: Split archives typically don't use encryption,
            # but they may use compression. For now, assume compression.
            # If encryption support is needed, add encrypted header detection here.
            next_header_data = decompress_encoded_header(next_header_data)
          end

          # Parse metadata - if data is incomplete due to missing volumes, handle gracefully
          parser = Parser.new(next_header_data)
          @stream_info, @entries = parse_metadata(parser)

          # Map entries to their folders/streams
          map_entries_to_streams
        rescue EOFError => e
          # Header data incomplete - likely missing volumes
          # Allow opening but with empty entries (graceful degradation)
          # This is an edge case where volumes were deleted after archive creation
          warn "WARNING: Archive header incomplete - missing volumes detected. Opening in degraded mode."
          warn "         Error: #{e.message}"
          @stream_info = Models::StreamInfo.new
          @entries = []
        end

        # Read data from volumes at global offset
        #
        # @param global_offset [Integer] Offset across all volumes
        # @param size [Integer] Number of bytes to read
        # @return [String] Read data
        def read_from_volumes(global_offset, size)
          data = String.new(encoding: "BINARY")
          remaining = size
          current_offset = global_offset

          @volume_handles.each_with_index do |handle, i|
            volume_size = File.size(@volumes[i])
            volume_start = i.zero? ? 0 : cumulative_size(i - 1)
            volume_end = volume_start + volume_size

            next if current_offset >= volume_end

            # Calculate read position in this volume
            unless current_offset >= volume_start && current_offset < volume_end
              next
            end

            local_offset = current_offset - volume_start
            available = volume_size - local_offset
            to_read = [available, remaining].min

            handle.seek(local_offset)
            chunk = handle.read(to_read)

            if chunk
              actual_read = chunk.bytesize
              data << chunk
              remaining -= actual_read
              current_offset += actual_read
            else
              # No data available - stop reading
              break
            end

            break if remaining.zero?
          end

          data
        end

        # Get cumulative size up to volume index
        #
        # @param index [Integer] Volume index
        # @return [Integer] Cumulative size in bytes
        def cumulative_size(index)
          @volumes[0..index].sum { |path| File.size(path) }
        end

        # Parse archive metadata
        #
        # @param parser [Parser] Parser instance
        # @return [Array<StreamInfo, Array<Models::FileEntry>>] Parsed data
        def parse_metadata(parser)
          stream_info = Models::StreamInfo.new
          entries = []

          # Read main header
          type = parser.read_byte
          raise "Expected Header, got 0x#{type.to_s(16)}" unless
            type == PropertyId::HEADER

          # Parse header sections
          until parser.eof?
            prop_type = parser.read_byte

            case prop_type
            when PropertyId::MAIN_STREAMS_INFO
              parse_streams_info(parser, stream_info)
            when PropertyId::FILES_INFO
              entries = parser.read_files_info
            when PropertyId::K_END
              break
            else
              # Skip unknown properties
              parser.skip_data if !parser.eof? &&
                parser.peek_byte != PropertyId::K_END
            end
          end

          parser.read_byte if !parser.eof? &&
            parser.peek_byte == PropertyId::K_END

          [stream_info, entries]
        end

        # Map entries to their folders and streams
        def map_entries_to_streams
          return if @stream_info.nil?

          stream_idx = 0
          @entries.each_with_index do |entry, i|
            next unless entry.has_stream?

            # Find which folder this stream belongs to
            folder_idx = 0
            accumulated = 0
            @stream_info.num_unpack_streams_in_folders.each_with_index do |num, fi|
              if stream_idx < accumulated + num
                folder_idx = fi
                break
              end
              accumulated += num
            end

            entry.folder_index = folder_idx
            entry.file_index = i
            entry.size = @stream_info.unpack_sizes[stream_idx] if @stream_info.unpack_sizes[stream_idx]
            stream_idx += 1
          end
        end

        # Decompress encoded (compressed) header
        #
        # @param encoded_data [String] Encoded header bytes
        # @return [String] Decompressed header data
        def decompress_encoded_header(encoded_data)
          # Skip ENCODED_HEADER marker
          parser = Parser.new(encoded_data[1..])

          # Parse the streams info for the encoded header
          stream_info = Models::StreamInfo.new

          # Read streams info - can be either MAIN_STREAMS_INFO or direct stream properties
          type = parser.read_byte

          if type == PropertyId::MAIN_STREAMS_INFO
            parse_streams_info(parser, stream_info)
          elsif type == PropertyId::PACK_INFO
            # Direct PackInfo without MAIN_STREAMS_INFO wrapper
            parser.read_pack_info(stream_info)

            # Read UNPACK_INFO
            type = parser.read_byte
            if type == PropertyId::UNPACK_INFO
              parser.read_unpack_info(stream_info)
            end
          else
            raise "Unexpected property in encoded header: 0x#{type.to_s(16)}"
          end

          # Decompress the header using the stream info
          pack_pos = @header.start_pos_after_header + stream_info.pack_pos
          folder = stream_info.folders[0]
          pack_size = stream_info.pack_sizes[0]
          unpack_size = folder.uncompressed_size

          # Create multi-volume IO wrapper for decompression
          io_wrapper = MultiVolumeIO.new(@volume_handles, @volumes)
          io_wrapper.seek(pack_pos)

          decompressor = StreamDecompressor.new(io_wrapper, folder, pack_pos,
                                                pack_size, @header)
          decompressor.decompress(unpack_size)
        end

        # Parse streams info section
        #
        # @param parser [Parser] Parser instance
        # @param stream_info [Models::StreamInfo] Stream info to populate
        def parse_streams_info(parser, stream_info)
          until parser.eof?
            prop_type = parser.read_byte

            case prop_type
            when PropertyId::PACK_INFO
              parser.read_pack_info(stream_info)
            when PropertyId::UNPACK_INFO
              parser.read_unpack_info(stream_info)
            when PropertyId::SUBSTREAMS_INFO
              parser.read_substreams_info(stream_info)
            when PropertyId::K_END
              break
            else
              # Unknown property within streams_info - skip it
              parser.skip_data if !parser.eof? && parser.peek_byte != PropertyId::K_END
            end
          end

          # Consume final K_END for MAIN_STREAMS_INFO section if present
          parser.read_byte if !parser.eof? && parser.peek_byte == PropertyId::K_END
        end

        # Extract entry data from volumes
        #
        # @param entry [Models::FileEntry] Entry to extract
        # @return [String] Extracted data
        def extract_entry_data(entry)
          return "" unless entry.has_stream?
          return "" unless @stream_info

          folder = @stream_info.folders[entry.folder_index]
          return "" unless folder

          # Calculate pack position in the combined stream
          # Start from where pack data begins (after header and any offset)
          pack_pos = @header.start_pos_after_header + @stream_info.pack_pos

          # Advance pack_pos by summing pack_sizes from previous folders
          # and find pack_idx for this folder
          pack_idx = 0
          entry.folder_index.times do |i|
            num_streams = @stream_info.folders[i].pack_stream_indices.size
            num_streams.times do |j|
              pack_pos += @stream_info.pack_sizes[pack_idx + j] || 0
            end
            pack_idx += num_streams
          end

          # Get pack size for this folder - use first pack stream only
          pack_size = @stream_info.pack_sizes[pack_idx] || 0

          # Create multi-volume IO wrapper
          io_wrapper = MultiVolumeIO.new(@volume_handles, @volumes)

          # For solid archives, multiple files share one compressed stream
          # We need to decompress the entire folder and extract the correct portion
          num_files_in_folder = @stream_info.num_unpack_streams_in_folders[entry.folder_index] || 1

          if num_files_in_folder > 1
            # Solid archive: decompress entire folder and extract this file's portion
            # Calculate total size by summing all stream sizes for this folder
            total_unpack_size = 0
            stream_idx = 0
            @stream_info.num_unpack_streams_in_folders.each_with_index do |num, fi|
              if fi == entry.folder_index
                # This is our folder - sum its stream sizes
                num.times do
                  total_unpack_size += @stream_info.unpack_sizes[stream_idx] || 0
                  stream_idx += 1
                end
                break
              else
                stream_idx += num
              end
            end

            decompressor = StreamDecompressor.new(io_wrapper, folder, pack_pos,
                                                  pack_size, @header)
            full_data = decompressor.decompress(total_unpack_size)

            # Find offset of this file within the uncompressed stream
            file_offset = 0
            @entries.each do |e|
              break if e.file_index == entry.file_index

              file_offset += e.size if e.has_stream? && e.folder_index == entry.folder_index
            end

            # Extract this file's data
            data = full_data[file_offset, entry.size]

            # Verify CRC if available
            if entry.crc
              crc = Omnizip::Checksums::Crc32.new
              crc.update(data)
              unless crc.value == entry.crc
                raise "CRC mismatch for #{entry.name}: expected 0x#{entry.crc.to_s(16)}, got 0x#{crc.value.to_s(16)}"
              end
            end

            data
          else
            # Non-solid: each file has its own compressed stream
            decompressor = StreamDecompressor.new(io_wrapper, folder, pack_pos,
                                                  pack_size, @header)
            expected_crc = entry.crc
            decompressor.decompress_and_verify(entry.size, expected_crc)
          end
        rescue StandardError => e
          warn "Extraction failed for #{entry.name}: #{e.message}"
          raise
        end

        # Multi-volume IO wrapper
        # Provides unified IO interface across multiple volumes
        class MultiVolumeIO
          def initialize(handles, paths)
            @handles = handles
            @paths = paths
            @position = 0
            @combined_data = nil
          end

          # Seek to position across volumes
          #
          # @param pos [Integer] Position to seek to
          # @param whence [Integer] Seek mode
          def seek(pos, whence = ::IO::SEEK_SET)
            case whence
            when ::IO::SEEK_SET
              @position = pos
            when ::IO::SEEK_CUR
              @position += pos
            when ::IO::SEEK_END
              @position = total_size + pos
            end
          end

          # Read from current position
          #
          # @param size [Integer] Number of bytes to read
          # @return [String, nil] Read data, or nil if at EOF
          def read(size)
            # Lazy-load combined data on first read
            if @combined_data.nil?
              load_combined_data
            end

            # Return nil if at EOF (matches IO behavior)
            return nil if @position >= @combined_data.bytesize

            available = @combined_data.bytesize - @position
            to_read = [size, available].min

            data = @combined_data[@position, to_read]
            @position += to_read

            data
          end

          # Get current position
          #
          # @return [Integer] Current position
          def pos
            @position
          end

          # Get total size across all volumes
          #
          # @return [Integer] Total size
          def total_size
            @paths.sum { |path| File.size(path) }
          end

          private

          # Load all volume data into memory
          def load_combined_data
            @combined_data = String.new(encoding: "BINARY")

            # Safety limit: prevent loading more than 10GB or 1000 volumes
            max_volumes = 1000
            max_size = 10 * 1024 * 1024 * 1024 # 10GB

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: MultiVolumeIO.load_combined_data - starting, volumes=#{@handles.size}"
            end

            @handles.each_with_index do |handle, idx|
              # Safety check: prevent infinite loop on corrupted archives
              if idx >= max_volumes
                warn "WARNING: Reached maximum volume limit (#{max_volumes}). Archive may be corrupted."
                break
              end

              if @combined_data.bytesize >= max_size
                warn "WARNING: Reached maximum data size limit (#{max_size} bytes). Archive may be corrupted."
                break
              end

              handle.rewind
              chunk = handle.read

              if ENV["LZMA2_DEBUG"]
                chunk_size = chunk&.bytesize || 0
                warn "DEBUG: MultiVolumeIO - loaded volume #{idx}: #{chunk_size} bytes, total=#{@combined_data.bytesize + chunk_size}"
              end

              @combined_data << chunk if chunk
            end

            if ENV["LZMA2_DEBUG"]
              warn "DEBUG: MultiVolumeIO.load_combined_data - complete, total_size=#{@combined_data.bytesize}"
            end
          end

          # Get cumulative size up to volume index
          #
          # @param index [Integer] Volume index
          # @return [Integer] Cumulative size
          def cumulative_size(index)
            @paths[0..index].sum { |path| File.size(path) }
          end
        end
      end
    end
  end
end

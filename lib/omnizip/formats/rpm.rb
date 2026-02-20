# frozen_string_literal: true

require "stringio"
require "tempfile"
require_relative "rpm/constants"
require_relative "rpm/lead"
require_relative "rpm/header"
require_relative "rpm/entry"
require_relative "cpio"

module Omnizip
  module Formats
    # RPM package format support
    #
    # Provides read access to RPM packages, extracting metadata
    # and file contents from the payload.
    #
    # @example Open RPM and list files
    #   Omnizip::Formats::Rpm.open('package.rpm') do |rpm|
    #     rpm.files.each { |f| puts f }
    #   end
    #
    # @example Extract RPM contents
    #   Omnizip::Formats::Rpm.extract('package.rpm', 'output/')
    module Rpm
      class << self
        # Open RPM package
        #
        # @param path [String] Path to RPM file
        # @yield [reader] Block for reading package
        # @yieldparam reader [Reader] RPM reader
        # @return [Reader]
        def open(path)
          reader = Reader.new(path)
          reader.open

          if block_given?
            begin
              yield reader
            ensure
              reader.close
            end
          else
            reader
          end
        end

        # List files in RPM
        #
        # @param path [String] Path to RPM file
        # @return [Array<String>] File paths
        def list(path)
          self.open(path, &:files)
        end

        # Extract RPM to directory
        #
        # @param rpm_path [String] Path to RPM file
        # @param output_dir [String] Output directory
        def extract(rpm_path, output_dir)
          self.open(rpm_path) do |rpm|
            rpm.extract(output_dir)
          end
        end

        # Get RPM information
        #
        # @param path [String] Path to RPM file
        # @return [Hash] Package information
        def info(path)
          self.open(path) do |rpm|
            {
              name: rpm.name,
              version: rpm.version,
              release: rpm.release,
              epoch: rpm.epoch,
              arch: rpm.architecture,
              summary: rpm.summary,
              description: rpm.description,
              license: rpm.license,
              vendor: rpm.vendor,
              build_time: rpm.build_time,
              file_count: rpm.files.size,
            }
          end
        end
      end

      # RPM package reader
      #
      # Handles parsing and extraction of RPM packages.
      class Reader
        include Constants

        # @return [String] File path
        attr_reader :path

        # @return [Lead] Parsed lead
        attr_reader :lead

        # @return [Header, nil] Signature header
        attr_reader :signature

        # @return [Header] Main header
        attr_reader :header

        # Initialize reader
        #
        # @param path [String] Path to RPM file
        def initialize(path)
          @path = path
          @file = nil
          @lead = nil
          @signature = nil
          @header = nil
          @tags = nil
        end

        # Open and parse RPM
        #
        # @return [self]
        def open
          @file = File.open(@path, "rb")
          parse!
          self
        end

        # Close file handle
        def close
          @file&.close
          @file = nil
        end

        # Get all tags as hash
        #
        # @return [Hash] Tag names to values
        def tags
          return @tags if @tags

          @tags = @header.to_h
        end

        # Get package name
        #
        # @return [String]
        def name
          tags[:name]
        end

        # Get package version
        #
        # @return [String]
        def version
          tags[:version]
        end

        # Get package release
        #
        # @return [String]
        def release
          tags[:release]
        end

        # Get package epoch
        #
        # @return [Integer, nil]
        def epoch
          tags[:epochnum] || tags[:epoch]&.first
        end

        # Get package architecture
        #
        # @return [String]
        def architecture
          tags[:arch]
        end

        # Get package summary
        #
        # @return [String]
        def summary
          tags[:summary]
        end

        # Get package description
        #
        # @return [String]
        def description
          tags[:description]
        end

        # Get package license
        #
        # @return [String]
        def license
          tags[:license]
        end

        # Get package vendor
        #
        # @return [String]
        def vendor
          tags[:vendor]
        end

        # Get build time
        #
        # @return [Time]
        def build_time
          Time.at(tags[:buildtime]&.first || 0)
        end

        # Get payload compressor
        #
        # @return [String] Compressor name (gzip, bzip2, xz, zstd)
        def payload_compressor
          tags[:payloadcompressor] || "gzip"
        end

        # Get list of files
        #
        # @return [Array<String>] File paths
        def files
          basenames = tags[:basenames] || []
          dirindexes = tags[:dirindexes] || []
          dirnames = tags[:dirnames] || []

          basenames.zip(dirindexes).map do |name, idx|
            File.join(dirnames[idx] || "", name || "")
          end
        end

        # Get file entries with metadata
        #
        # @return [Array<Entry>]
        def entries
          paths = files
          sizes = tags[:filesizes] || []
          modes = tags[:filemodes] || []
          uids = tags[:fileuids] || []
          gids = tags[:filegids] || []
          mtimes = tags[:filemtimes] || []
          flags = tags[:fileflags] || []
          users = tags[:fileusername] || []
          groups = tags[:filegroupname] || []
          digests = tags[:filedigests] || []
          linktos = tags[:filelinktos] || []

          paths.each_with_index.map do |path, i|
            Entry.new.tap do |entry|
              entry.path = path
              entry.size = sizes[i] || 0
              entry.mode = modes[i] || 0o100_644
              entry.uid = uids[i] || 0
              entry.gid = gids[i] || 0
              entry.mtime = Time.at(mtimes[i] || 0)
              entry.flags = flags[i] || 0
              entry.user = users[i] || ""
              entry.group = groups[i] || ""
              entry.digest = digests[i] || ""
              entry.link_to = linktos[i] || ""
            end
          end
        end

        # Get requires
        #
        # @return [Array<Array>] [name, operator, version]
        def requires
          build_relations(:require)
        end

        # Get provides
        #
        # @return [Array<Array>] [name, operator, version]
        def provides
          build_relations(:provide)
        end

        # Get conflicts
        #
        # @return [Array<Array>] [name, operator, version]
        def conflicts
          build_relations(:conflict)
        end

        # Extract to directory
        #
        # @param output_dir [String] Output directory
        def extract(output_dir)
          raise "RPM not opened" unless @file

          FileUtils.mkdir_p(output_dir)

          # Get payload IO
          payload_io = payload

          # Decompress payload using appropriate decompressor
          decompressor = create_decompressor(payload_io)

          # Parse CPIO from decompressed stream
          extract_cpio(decompressor, output_dir)
        end

        # Get raw payload data
        #
        # Returns the compressed payload as-is (without decompression).
        # Useful for saving the payload as a file (e.g., fonts.src.cpio.gz).
        #
        # @return [String] Raw compressed payload data
        def raw_payload
          raise "RPM not opened" unless @file

          payload_io = payload
          payload_io.read
        end

        private

        def parse!
          # Parse lead
          @lead = Lead.parse(@file)

          # Parse signature header if present
          if @lead.signature_type == HEADER_SIGNED_TYPE
            @signature = Header.parse(@file)

            # Skip padding to 8-byte boundary
            padding = @signature.length % 8
            @file.read(padding) if padding.positive?
          end

          # Parse main header
          @header = Header.parse(@file)
        end

        def build_relations(type)
          names = tags[:"#{type}name"]
          flags = tags[:"#{type}flags"]
          versions = tags[:"#{type}version"]

          return [] unless names && flags && versions

          names.zip(flags, versions).map do |name, flag, version|
            [name, operator_from_flag(flag), version]
          end
        end

        def operator_from_flag(flag)
          return ">=" if flag.anybits?(FLAG_GREATER) && flag.anybits?(FLAG_EQUAL)
          return "<=" if flag.anybits?(FLAG_LESS) && flag.anybits?(FLAG_EQUAL)
          return ">" if flag.anybits?(FLAG_GREATER)
          return "<" if flag.anybits?(FLAG_LESS)
          return "=" if flag.anybits?(FLAG_EQUAL)

          ""
        end

        def payload
          raise "RPM not opened" unless @file

          # Calculate payload offset
          offset = @lead.length
          offset += @signature.length if @signature
          offset += (@signature.length % 8) if @signature
          offset += @header.length

          # Create copy of file positioned at payload
          payload_file = @file.dup
          payload_file.seek(offset)
          payload_file
        end

        def create_decompressor(io)
          compressor = payload_compressor

          case compressor
          when "gzip"
            require "zlib"
            Zlib::GzipReader.new(io)
          when "bzip2"
            require_relative "../algorithms/bzip2/decompressor"
            # Bzip2 decompressor needs the whole data
            Omnizip::Algorithms::Bzip2::Decompressor.new.decompress(io.read)
          when "xz", "lzma"
            # XZ decompressor
            decompress_xz(io)
          when "zstd"
            decompress_zstd(io)
          else
            # Unknown, try raw
            io
          end
        end

        def decompress_xz(io)
          require_relative "xz"
          Xz.decode(io.read)
        end

        # Decompress zstd payload using system command (fallback for complex zstd format)
        def decompress_zstd(io)
          data = io.read

          # Use system zstd command for reliable decompression
          # Pure Ruby decoder has incomplete FSE table support
          decompress_with_command("zstd", "-d", "-c", data)
        end

        # Decompress data using external command
        def decompress_with_command(cmd, *args, data)
          require "open3"

          output = +""
          Open3.popen3(cmd, *args) do |stdin, stdout, _stderr, wait_thr|
            stdin.binmode
            stdout.binmode
            stdin.write(data)
            stdin.close
            output = stdout.read
            wait_thr.value
          end

          output
        rescue StandardError => e
          raise "Failed to decompress with #{cmd}: #{e.message}"
        end

        def extract_cpio(source, output_dir)
          # Create temp file for CPIO data
          Tempfile.create(["rpm_payload", ".cpio"]) do |temp|
            temp.binmode
            if source.is_a?(String)
              temp.write(source)
            else
              temp.write(source.read)
            end
            temp.flush

            # Use CPIO reader to extract
            Cpio.extract(temp.path, output_dir)
          end
        end
      end
    end
  end
end

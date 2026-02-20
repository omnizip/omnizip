# frozen_string_literal: true

require "set"
require "zlib"
require "stringio"
require "digest"
require_relative "constants"
require_relative "lead"
require_relative "header"
require_relative "tag"
require_relative "../cpio/writer"

module Omnizip
  module Formats
    module Rpm
      # RPM package writer
      #
      # Creates RPM packages with binary payload (CPIO archive).
      # Supports gzip compression for the payload.
      #
      # @example Create an RPM package
      #   writer = Rpm::Writer.new(
      #     name: "myapp",
      #     version: "1.0.0",
      #     release: "1",
      #     arch: "x86_64"
      #   )
      #   writer.add_file("/usr/bin/myapp", content, mode: 0755)
      #   writer.add_directory("/etc/myapp")
      #   writer.add_file("/etc/myapp/config.yml", config_content)
      #   writer.write("myapp-1.0.0-1.x86_64.rpm")
      #
      class Writer
        include Constants

        # Architecture mapping
        ARCHITECTURES = {
          "noarch" => 0,
          "i386" => 1,
          "i486" => 2,
          "i586" => 3,
          "i686" => 4,
          "x86_64" => 9,
          "amd64" => 9,
          "ia64" => 11,
          "ppc" => 5,
          "ppc64" => 16,
          "sparc" => 6,
          "sparc64" => 7,
          "alpha" => 8,
          "s390" => 14,
          "s390x" => 15,
          "arm" => 12,
          "aarch64" => 19,
        }.freeze

        # Tag ID mapping (reverse of Tag::TAG_IDS)
        TAG_NAMES = {
          # Header tags
          name: 1000,
          version: 1001,
          release: 1002,
          epoch: 1003,
          summary: 1004,
          description: 1005,
          buildtime: 1006,
          buildhost: 1007,
          size: 1009,
          distribution: 1010,
          vendor: 1011,
          license: 1014,
          packager: 1015,
          group: 1016,
          url: 1020,
          os: 1021,
          arch: 1022,
          prein: 1023,
          postin: 1024,
          preun: 1025,
          postun: 1026,
          filesizes: 1028,
          filemodes: 1030,
          fileuids: 1031,
          filegids: 1032,
          filemtimes: 1034,
          filedigests: 1035,
          filelinktos: 1036,
          fileflags: 1037,
          fileusername: 1039,
          filegroupname: 1040,
          archivesize: 1046,
          rpmversion: 1064,
          dirindexes: 1116,
          basenames: 1117,
          dirnames: 1118,
          payloadformat: 1124,
          payloadcompressor: 1125,
          payloadflags: 1126,

          # Signature tags
          sigsize: 257,
          sha1header: 269,
        }.freeze

        # @return [String] Package name
        attr_reader :name

        # @return [String] Package version
        attr_reader :version

        # @return [String] Package release
        attr_reader :release

        # @return [String, nil] Package epoch
        attr_reader :epoch

        # @return [String] Architecture
        attr_reader :arch

        # @return [Hash<String, String>] File contents
        attr_reader :files

        # @return [Hash] Additional metadata
        attr_reader :metadata

        # Initialize RPM writer
        #
        # @param name [String] Package name
        # @param version [String] Package version
        # @param release [String] Package release
        # @param arch [String] Architecture (default: "noarch")
        # @param epoch [String, nil] Optional epoch
        # @param metadata [Hash] Additional metadata
        def initialize(name:, version:, release:, arch: "noarch", epoch: nil, **metadata)
          @name = name
          @version = version
          @release = release
          @arch = arch
          @epoch = epoch
          @metadata = metadata
          @files = []
          @directories = []
          @compression = :gzip
        end

        # Add file to package
        #
        # @param path [String] File path in package (absolute path)
        # @param content [String] File content
        # @param mode [Integer] File permissions (default: 0644)
        # @param owner [String] File owner (default: "root")
        # @param group [String] File group (default: "root")
        # @param mtime [Integer] Modification time (default: now)
        def add_file(path, content, mode: 0o644, owner: "root", group: "root", mtime: nil)
          @files << {
            path: path,
            content: content,
            mode: mode,
            owner: owner,
            group: group,
            mtime: mtime || Time.now.to_i,
          }
        end

        # Add directory to package
        #
        # @param path [String] Directory path in package (absolute path)
        # @param mode [Integer] Directory permissions (default: 0755)
        # @param owner [String] Directory owner (default: "root")
        # @param group [String] Directory group (default: "root")
        def add_directory(path, mode: 0o755, owner: "root", group: "root")
          @directories << {
            path: path,
            mode: mode,
            owner: owner,
            group: group,
          }
        end

        # Write RPM package to file
        #
        # @param output_path [String] Output file path
        # @return [String] Output path
        def write(output_path)
          File.open(output_path, "wb") do |io|
            write_to_io(io)
          end
          output_path
        end

        # Write RPM package to IO
        #
        # @param io [IO] Output IO
        def write_to_io(io)
          # Build payload (compressed CPIO)
          payload_io = StringIO.new("".b)
          cpio_data = build_cpio_payload
          compress_payload(cpio_data, payload_io)
          payload_io.rewind
          payload_data = payload_io.read

          # Build headers
          main_header = build_main_header(payload_data.bytesize)
          sig_header = build_signature_header(main_header.bytesize, payload_data.bytesize)

          # Build lead
          lead = build_lead

          # Write RPM in order
          io.write(lead)
          io.write(sig_header)
          io.write(main_header)
          io.write(payload_data)
        end

        private

        # Build lead (96 bytes)
        #
        # @return [String] Packed lead
        def build_lead
          name_field = "#{@name}-#{@version}-#{@release}"
          name_field = name_field[0, 65] # Truncate to 65 chars + null
          name_padded = name_field.ljust(66, "\0")

          arch_num = ARCHITECTURES.fetch(@arch.downcase, 0)

          # Pack format:
          # A4 = magic (4 bytes)
          # CC = major/minor version (2 bytes)
          # n = package type (2 bytes, 0 = binary)
          # n = architecture (2 bytes)
          # A66 = name (66 bytes)
          # n = os (2 bytes, 1 = Linux)
          # n = signature type (2 bytes, 5 = signed)
          # A16 = reserved (16 bytes)
          [LEAD_MAGIC, 3, 0, PACKAGE_BINARY, arch_num, name_padded, 1,
           HEADER_SIGNED_TYPE, "\0" * 16].pack("A4 CC n n A66 n n A16")
        end

        # Build signature header
        #
        # @param header_size [Integer] Main header size
        # @param payload_size [Integer] Payload size
        # @return [String] Packed signature header
        def build_signature_header(header_size, payload_size)
          tags = [
            { id: TAG_NAMES[:sigsize], type: TYPE_INT32, value: [header_size + payload_size] },
            { id: TAG_NAMES[:sha1header], type: TYPE_STRING, value: "" },
          ]
          build_header_data(tags)
        end

        # Build main header
        #
        # @param payload_size [Integer] Payload size (uncompressed)
        # @return [String] Packed main header
        def build_main_header(payload_size)
          # Build file lists
          dirnames = []
          basenames = []
          dirindexes = []
          filemodes = []
          filesizes = []
          fileowners = []
          filegroups = []
          filemtimes = []
          filedigests = []
          filelinktos = []
          fileflags = []

          # Process directories first
          dir_set = Set.new
          @directories.each do |dir|
            dir_path = dir[:path]
            parent = File.dirname(dir_path.sub(%r{/+$}, ""))
            dir_name = File.basename(dir_path.sub(%r{/+$}, ""))

            dir_set.size
            dir_set << dir_path

            # Parent directory for relative path
            parent_dir = parent == "." ? "/" : parent
            dirnames.size
            dirnames << parent_dir unless dirnames.include?(parent_dir)
            parent_index = dirnames.index(parent_dir)

            basenames << dir_name
            dirindexes << parent_index
            filemodes << (dir[:mode] | 0o040000) # Directory flag
            filesizes << 4096 # Typical directory size
            fileowners << dir[:owner]
            filegroups << dir[:group]
            filemtimes << Time.now.to_i
            filedigests << ""
            filelinktos << ""
            fileflags << 0
          end

          # Process files
          @files.each do |file|
            file_path = file[:path]
            parent_dir = File.dirname(file_path)
            base_name = File.basename(file_path)

            # Ensure directory is in list
            dir_index = dirnames.index(parent_dir)
            dir_index ||= dirnames.size.tap { dirnames << parent_dir }

            basenames << base_name
            dirindexes << dir_index
            filemodes << file[:mode]
            filesizes << file[:content].bytesize
            fileowners << file[:owner]
            filegroups << file[:group]
            filemtimes << file[:mtime]
            filedigests << Digest::MD5.hexdigest(file[:content])
            filelinktos << ""
            fileflags << 0
          end

          tags = [
            { id: TAG_NAMES[:name], type: TYPE_STRING, value: @name },
            { id: TAG_NAMES[:version], type: TYPE_STRING, value: @version },
            { id: TAG_NAMES[:release], type: TYPE_STRING, value: @release },
            { id: TAG_NAMES[:arch], type: TYPE_STRING, value: @arch },
            { id: TAG_NAMES[:os], type: TYPE_STRING, value: "linux" },
            { id: TAG_NAMES[:rpmversion], type: TYPE_STRING, value: "4.16.0" },
            { id: TAG_NAMES[:payloadformat], type: TYPE_STRING, value: "cpio" },
            { id: TAG_NAMES[:payloadcompressor], type: TYPE_STRING, value: "gzip" },
            { id: TAG_NAMES[:payloadflags], type: TYPE_STRING, value: "9" },
            { id: TAG_NAMES[:archivesize], type: TYPE_INT32, value: [payload_size] },
            { id: TAG_NAMES[:dirnames], type: TYPE_STRING_ARRAY, value: dirnames },
            { id: TAG_NAMES[:basenames], type: TYPE_STRING_ARRAY, value: basenames },
            { id: TAG_NAMES[:dirindexes], type: TYPE_INT32, value: dirindexes },
            { id: TAG_NAMES[:filemodes], type: TYPE_INT16, value: filemodes },
            { id: TAG_NAMES[:filesizes], type: TYPE_INT32, value: filesizes },
            { id: TAG_NAMES[:fileusername], type: TYPE_STRING_ARRAY, value: fileowners },
            { id: TAG_NAMES[:filegroupname], type: TYPE_STRING_ARRAY, value: filegroups },
            { id: TAG_NAMES[:filemtimes], type: TYPE_INT32, value: filemtimes },
            { id: TAG_NAMES[:filedigests], type: TYPE_STRING_ARRAY, value: filedigests },
            { id: TAG_NAMES[:filelinktos], type: TYPE_STRING_ARRAY, value: filelinktos },
            { id: TAG_NAMES[:fileflags], type: TYPE_INT32, value: fileflags },
          ]

          # Add optional metadata
          {
            summary: TYPE_STRING,
            description: TYPE_STRING,
            license: TYPE_STRING,
            group: TYPE_STRING,
            url: TYPE_STRING,
            vendor: TYPE_STRING,
            packager: TYPE_STRING,
          }.each do |key, type|
            value = @metadata[key]
            tags << { id: TAG_NAMES[key], type: type, value: value } if value
          end

          tags << { id: TAG_NAMES[:epoch], type: TYPE_INT32, value: [@epoch.to_i] } if @epoch

          build_header_data(tags)
        end

        # Build header data structure
        #
        # @param tags [Array<Hash>] Array of tag definitions
        # @return [String] Packed header
        def build_header_data(tags)
          # Build data blob and tag entries
          data_blob = "".b
          tag_entries = []

          tags.each do |tag_def|
            offset = data_blob.bytesize
            value = tag_def[:value]
            type = tag_def[:type]

            packed_data = pack_tag_value(type, value)
            data_blob << packed_data

            count = case type
                    when TYPE_STRING_ARRAY
                      value.is_a?(Array) ? value.size : 1
                    when TYPE_STRING
                      1
                    else
                      value.is_a?(Array) ? value.size : 1
                    end

            tag_entries << [tag_def[:id], type, offset, count].pack("NNNN")
          end

          # Build complete header
          entry_count = tags.size
          data_length = data_blob.bytesize

          # Pad data blob to 8-byte boundary
          padding = (8 - (data_length % 8)) % 8
          data_blob << ("\0" * padding)

          # Header header: magic (8) + entry_count (4) + data_length (4)
          header_header = [HEADER_MAGIC, entry_count, data_blob.bytesize].pack("A8 NN")

          header_header + tag_entries.join + data_blob
        end

        # Pack tag value based on type
        #
        # @param type [Integer] Tag type
        # @param value [Object] Value to pack
        # @return [String] Packed data
        def pack_tag_value(type, value)
          case type
          when TYPE_STRING
            "#{value}\0".b
          when TYPE_STRING_ARRAY
            value.map { |v| "#{v}\0" }.join.b
          when TYPE_INT8
            [value].flatten.pack("C*")
          when TYPE_INT16
            [value].flatten.pack("n*")
          when TYPE_INT32
            [value].flatten.pack("N*")
          when TYPE_INT64
            [value].flatten.pack("Q>")
          when TYPE_BINARY
            value.b
          else
            value.to_s.b
          end
        end

        # Build CPIO payload
        #
        # @return [String] CPIO archive data
        def build_cpio_payload
          cpio_io = StringIO.new("".b)

          # Write directories
          @directories.each do |dir|
            entry_data = build_cpio_directory_entry(dir)
            cpio_io.write(entry_data)
          end

          # Write files
          @files.each do |file|
            entry_data = build_cpio_file_entry(file)
            cpio_io.write(entry_data)
          end

          # Write trailer
          cpio_io.write(build_cpio_trailer)

          cpio_io.string
        end

        # Build CPIO directory entry
        #
        # @param dir [Hash] Directory info
        # @return [String] Packed CPIO entry
        def build_cpio_directory_entry(dir)
          mode = dir[:mode] | 0o040000 # Directory flag
          path = dir[:path].sub(%r{/+$}, "") # Remove trailing slashes

          build_cpio_entry(path, "", mode)
        end

        # Build CPIO file entry
        #
        # @param file [Hash] File info
        # @return [String] Packed CPIO entry
        def build_cpio_file_entry(file)
          build_cpio_entry(file[:path], file[:content], file[:mode])
        end

        # Build CPIO entry (newc format)
        #
        # @param path [String] Entry path
        # @param data [String] Entry data
        # @param mode [Integer] File mode
        # @return [String] Packed CPIO entry
        def build_cpio_entry(path, data, mode)
          name = path.start_with?("/") ? path[1..] : path
          namesize = name.bytesize + 1
          filesize = data.bytesize

          inode = @inode_counter ||= 1
          @inode_counter += 1

          # Build header (110 bytes for newc)
          header = format(
            "070701%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%08x%s\x00",
            inode,           # inode
            mode,            # mode
            0,               # uid
            0,               # gid
            1,               # nlink
            Time.now.to_i,   # mtime
            filesize,        # filesize
            0,               # devmajor
            0,               # devminor
            0,               # rdevmajor
            0,               # rdevminor
            namesize,        # namesize
            0,               # checksum (0 for newc)
            name, # name
          )

          # Pad header to 4-byte boundary
          header_padding = (4 - (header.bytesize % 4)) % 4
          header << ("\0" * header_padding)

          # Pad data to 4-byte boundary
          data_padding = (4 - (filesize % 4)) % 4

          header + data + ("\0" * data_padding)
        end

        # Build CPIO trailer
        #
        # @return [String] Trailer entry
        def build_cpio_trailer
          build_cpio_entry("TRAILER!!!", "", 0)
        end

        # Compress payload
        #
        # @param data [String] Uncompressed data
        # @param output [IO] Output IO for compressed data
        def compress_payload(data, output)
          case @compression
          when :gzip
            gz = Zlib::GzipWriter.new(output, 9)
            gz.write(data)
            gz.finish
          when :none
            output.write(data)
          else
            raise ArgumentError, "Unsupported compression: #{@compression}"
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require "set"
require "zlib"
require "time"
require "rexml/document"
require_relative "constants"
require_relative "entry"

module Omnizip
  module Formats
    module Xar
      # XAR Table of Contents (TOC) parser and builder
      #
      # The TOC is a GZIP-compressed XML document that contains:
      # - Archive metadata (creation time, checksum info)
      # - File hierarchy with metadata for each entry
      # - Data offsets and sizes in the heap
      # - Extended attributes
      class Toc
        include Constants

        attr_accessor :creation_time, :checksum_offset, :checksum_size,
                      :checksum_style
        attr_reader :entries

        # Parse TOC from compressed data
        #
        # @param compressed_data [String] GZIP-compressed TOC XML
        # @param uncompressed_size [Integer] Expected uncompressed size
        # @return [Toc] Parsed TOC object
        def self.parse(compressed_data, uncompressed_size = nil)
          uncompressed = decompress(compressed_data, uncompressed_size)
          xml_doc = REXML::Document.new(uncompressed)
          from_xml(xml_doc)
        end

        # Decompress TOC data
        #
        # @param compressed_data [String] Zlib-compressed data
        # @param expected_size [Integer, nil] Expected size for validation
        # @return [String] Decompressed XML
        def self.decompress(compressed_data, expected_size = nil)
          # XAR TOC is zlib compressed (with zlib headers, 0x78xx)
          # Try zlib format first (most common), then fall back to raw deflate
          result = begin
            # Try standard zlib format (with header)
            Zlib::Inflate.inflate(compressed_data)
          rescue Zlib::DataError
            # Fall back to raw deflate for non-conforming implementations
            Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(compressed_data)
          end

          if expected_size && result.bytesize != expected_size
            raise ArgumentError,
                  "TOC size mismatch: #{result.bytesize} != #{expected_size}"
          end

          result
        end

        # Parse TOC from XML document
        #
        # @param xml_doc [REXML::Document] Parsed XML document
        # @return [Toc] Parsed TOC object
        def self.from_xml(xml_doc)
          toc = new
          root = xml_doc.root

          return toc unless root&.name == "xar"

          toc_element = root.elements["toc"]
          return toc unless toc_element

          # Parse creation time
          if (ctime = toc_element.elements["creation-time"]&.text)
            toc.creation_time = parse_timestamp(ctime)
          end

          # Parse checksum info
          if (checksum = toc_element.elements["checksum"])
            toc.checksum_style = checksum.attributes["style"] || "sha1"
            toc.checksum_offset = checksum.elements["offset"]&.text.to_i
            toc.checksum_size = checksum.elements["size"]&.text.to_i
          end

          # Parse file entries
          toc_element.elements.each("file") do |file_elem|
            entry = parse_file_element(file_elem)
            toc.add_entry(entry)

            # Parse nested files (subdirectories)
            parse_nested_files(file_elem, entry, toc)
          end

          toc
        end

        # Initialize TOC
        def initialize
          @creation_time = Time.now
          @entries = []
          @checksum_offset = 0
          @checksum_size = 0
          @checksum_style = DEFAULT_TOC_CHECKSUM
          @next_id = 1
        end

        # Set creation time

        # Add entry to TOC
        #
        # @param entry [Entry] Entry to add
        # @return [Entry] The added entry
        def add_entry(entry)
          entry.id ||= @next_id
          @next_id = [@next_id, entry.id + 1].max
          @entries << entry
          entry
        end

        # Get next available ID
        #
        # @return [Integer] Next ID
        def next_id
          @next_id
        end

        # Find entry by name
        #
        # @param name [String] Entry name
        # @return [Entry, nil] Found entry or nil
        def find_entry(name)
          @entries.find { |e| e.name == name }
        end

        # Find entry by ID
        #
        # @param id [Integer] Entry ID
        # @return [Entry, nil] Found entry or nil
        def find_entry_by_id(id)
          @entries.find { |e| e.id == id }
        end

        # Generate XML document
        #
        # @return [REML::Document] XML document
        def to_xml
          doc = REXML::Document.new
          doc.add(REXML::XMLDecl.new("1.0", "UTF-8"))

          root = doc.add_element("xar")
          toc_element = root.add_element("toc")

          # Add creation time
          ctime_elem = toc_element.add_element("creation-time")
          ctime_elem.add_text(@creation_time.to_f.to_s)

          # Add checksum info
          checksum_elem = toc_element.add_element("checksum")
          checksum_elem.add_attribute("style", @checksum_style)
          offset_elem = checksum_elem.add_element("offset")
          offset_elem.add_text(@checksum_offset.to_s)
          size_elem = checksum_elem.add_element("size")
          size_elem.add_text(@checksum_size.to_s)

          # Add file entries
          build_file_tree(toc_element)

          doc
        end

        # Generate XML string
        #
        # @return [String] XML string
        def to_xml_string
          output = +""
          doc = to_xml
          doc.write(output: output, indent: 2)
          output
        end

        # Compress TOC XML
        #
        # @return [String] GZIP-compressed XML
        def compress
          xml = to_xml_string

          zlib = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
          result = zlib.deflate(xml, Zlib::FINISH)
          zlib.close
          result
        end

        # Get uncompressed size
        #
        # @return [Integer] Uncompressed XML size
        def uncompressed_size
          to_xml_string.bytesize
        end

        private

        # Parse timestamp from string
        #
        # @param value [String] Timestamp string
        # @return [Time] Parsed time
        def self.parse_timestamp(value)
          value = text_content(value)
          case value
          when /\A\d+\.\d+\z/
            Time.at(value.to_f)
          when /\A\d+\z/
            Time.at(value.to_i)
          else
            Time.parse(value)
          end
        end
        private_class_method :parse_timestamp

        # Get text content from element, stripping whitespace
        #
        # @param elem [REXML::Element, String, nil] Element or text
        # @return [String, nil] Stripped text or nil
        def self.text_content(elem)
          return nil if elem.nil?

          text = elem.respond_to?(:text) ? elem.text : elem.to_s
          text&.strip
        end
        private_class_method :text_content

        # Get integer from element text
        #
        # @param elem [REXML::Element, nil] Element
        # @return [Integer, nil] Integer value or nil
        def self.int_content(elem)
          text = text_content(elem)
          text&.to_i
        end
        private_class_method :int_content

        # Parse file element from XML
        #
        # @param elem [REXML::Element] File element
        # @return [Entry] Parsed entry
        def self.parse_file_element(elem)
          options = {}

          options[:id] = elem.attributes["id"]&.to_i

          # Name
          options[:name] = text_content(elem.elements["name"]) || ""

          # Type
          options[:type] = text_content(elem.elements["type"]) || TYPE_FILE

          # Mode
          if (mode = text_content(elem.elements["mode"]))
            options[:mode] = mode.to_i(8)
          end

          # Owner info
          options[:uid] = int_content(elem.elements["uid"])
          options[:gid] = int_content(elem.elements["gid"])
          options[:user] = text_content(elem.elements["user"])
          options[:group] = text_content(elem.elements["group"])

          # Size
          if (size = text_content(elem.elements["size"]))
            options[:size] = size.to_i
          end

          # Timestamps
          if (ctime = elem.elements["ctime"])
            options[:ctime] = parse_timestamp(ctime)
          end
          if (mtime = elem.elements["mtime"])
            options[:mtime] = parse_timestamp(mtime)
          end
          if (atime = elem.elements["atime"])
            options[:atime] = parse_timestamp(atime)
          end

          # Data section
          if (data = elem.elements["data"])
            options[:data_offset] = int_content(data.elements["offset"]) || 0
            # In XAR format:
            # - <length> is the uncompressed (extracted) size
            # - <size> is the compressed (archived) size
            options[:data_size] = int_content(data.elements["length"]) || 0
            options[:data_length] = int_content(data.elements["size"]) || 0

            if (encoding = data.elements["encoding"])
              style = encoding.attributes["style"]
              options[:data_encoding] = MIME_TYPE_TO_COMPRESSION[style] || style
            end

            if (archived_sum = data.elements["archived-checksum"])
              options[:archived_checksum] = text_content(archived_sum)
              options[:archived_checksum_style] =
                archived_sum.attributes["style"]
            end

            if (extracted_sum = data.elements["extracted-checksum"])
              options[:extracted_checksum] = text_content(extracted_sum)
              options[:extracted_checksum_style] =
                extracted_sum.attributes["style"]
            end
          end

          # Link info
          if (link = elem.elements["link"])
            options[:link_type] = link.attributes["type"]
            options[:link_target] = text_content(link)
          end

          # Device info
          if (device = elem.elements["device"])
            options[:device_major] = int_content(device.elements["major"])
            options[:device_minor] = int_content(device.elements["minor"])
          end

          # Extended attributes
          ea_list = []
          elem.elements.each("ea") do |ea_elem|
            attr = Entry::ExtendedAttribute.new(name: text_content(ea_elem.elements["name"]))
            attr.id = ea_elem.attributes["id"]&.to_i

            if (ea_data = ea_elem.elements["data"])
              attr.data_offset = int_content(ea_data.elements["offset"]) || 0
              attr.data_length = int_content(ea_data.elements["length"]) || 0
              attr.data_size = int_content(ea_data.elements["size"]) || 0
            end

            ea_list << attr
          end
          options[:ea] = ea_list unless ea_list.empty?

          # Flags
          options[:flags] = elem.elements["flags"]&.text

          # Inode info
          options[:ino] = elem.elements["ino"]&.text&.to_i

          Entry.new(options[:name], options)
        end
        private_class_method :parse_file_element

        # Parse nested files recursively
        #
        # @param elem [REXML::Element] Parent element
        # @param parent_entry [Entry] Parent entry
        # @param toc [Toc] TOC object
        def self.parse_nested_files(elem, parent_entry, toc)
          elem.elements.each("file") do |file_elem|
            entry = parse_file_element(file_elem)
            # Prepend parent path to name
            unless parent_entry.name.empty?
              entry.name = File.join(parent_entry.name,
                                     entry.name)
            end
            toc.add_entry(entry)

            # Recurse for deeper nesting
            parse_nested_files(file_elem, entry, toc)
          end
        end
        private_class_method :parse_nested_files

        # Build file tree for XML output
        #
        # @param toc_element [REXML::Element] TOC element
        def build_file_tree(toc_element)
          # Group entries by parent path
          root_entries = []
          children_by_parent = {}
          known_parents = Set.new

          @entries.each do |entry|
            known_parents << entry.name if entry.directory?

            parent = File.dirname(entry.name)
            # Entry is a root if:
            # 1. It has no parent path (parent == "." or parent == entry.name)
            # 2. Its parent directory is not in the archive
            if parent == "." || parent == entry.name || !known_parents.include?(parent)
              root_entries << entry
            else
              children_by_parent[parent] ||= []
              children_by_parent[parent] << entry
            end
          end

          # Build XML for root entries
          root_entries.each do |entry|
            add_file_element(toc_element, entry, children_by_parent)
          end
        end

        # Add file element to XML
        #
        # @param parent_elem [REXML::Element] Parent element
        # @param entry [Entry] Entry to add
        # @param children_map [Hash] Children by parent path
        # @param parent_path [String] Path of parent directory (for nested entries)
        def add_file_element(parent_elem, entry, children_map,
parent_path = nil)
          file_elem = parent_elem.add_element("file")
          file_elem.add_attribute("id", entry.id.to_s)

          # Name - use full path for root entries, basename for nested
          name_elem = file_elem.add_element("name")
          if parent_path
            # Nested entry - use just the basename
            name_elem.add_text(File.basename(entry.name))
          else
            # Root entry - use full path
            name_elem.add_text(entry.name)
          end

          # Type
          type_elem = file_elem.add_element("type")
          type_elem.add_text(entry.type)

          # Mode
          if entry.mode
            mode_elem = file_elem.add_element("mode")
            mode_elem.add_text(format("0%03o", entry.mode))
          end

          # Owner info
          if entry.uid
            uid_elem = file_elem.add_element("uid")
            uid_elem.add_text(entry.uid.to_s)
          end
          if entry.gid
            gid_elem = file_elem.add_element("gid")
            gid_elem.add_text(entry.gid.to_s)
          end
          if entry.user && !entry.user.empty?
            user_elem = file_elem.add_element("user")
            user_elem.add_text(entry.user)
          end
          if entry.group && !entry.group.empty?
            group_elem = file_elem.add_element("group")
            group_elem.add_text(entry.group)
          end

          # Size
          if entry.size&.positive?
            size_elem = file_elem.add_element("size")
            size_elem.add_text(entry.size.to_s)
          end

          # Timestamps
          add_timestamp(file_elem, "ctime", entry.ctime) if entry.ctime
          add_timestamp(file_elem, "mtime", entry.mtime) if entry.mtime
          add_timestamp(file_elem, "atime", entry.atime) if entry.atime

          # Data section
          if entry.data_size&.positive?
            data_elem = file_elem.add_element("data")

            offset_elem = data_elem.add_element("offset")
            offset_elem.add_text(entry.data_offset.to_s)

            # In XAR format:
            # - <length> is the uncompressed (extracted) size
            # - <size> is the compressed (archived) size
            if entry.data_size&.positive?
              length_elem = data_elem.add_element("length")
              length_elem.add_text(entry.data_size.to_s)
            end

            if entry.data_length&.positive?
              size_elem = data_elem.add_element("size")
              size_elem.add_text(entry.data_length.to_s)
            end

            if entry.data_encoding && entry.data_encoding != COMPRESSION_NONE
              encoding_elem = data_elem.add_element("encoding")
              mime = COMPRESSION_MIME_TYPES[entry.data_encoding] || entry.data_encoding
              encoding_elem.add_attribute("style", mime)
            end

            add_checksum(data_elem, "archived-checksum",
                         entry.archived_checksum_style, entry.archived_checksum)
            add_checksum(data_elem, "extracted-checksum",
                         entry.extracted_checksum_style, entry.extracted_checksum)
          end

          # Link
          if entry.link_target
            link_elem = file_elem.add_element("link")
            link_elem.add_attribute("type", entry.link_type) if entry.link_type
            link_elem.add_text(entry.link_target)
          end

          # Device
          if entry.device?
            device_elem = file_elem.add_element("device")
            if entry.device_major
              major_elem = device_elem.add_element("major")
              major_elem.add_text(entry.device_major.to_s)
            end
            if entry.device_minor
              minor_elem = device_elem.add_element("minor")
              minor_elem.add_text(entry.device_minor.to_s)
            end
          end

          # Extended attributes
          entry.ea&.each do |attr|
            ea_elem = file_elem.add_element("ea")
            ea_elem.add_attribute("id", attr.id.to_s) if attr.id

            name_elem = ea_elem.add_element("name")
            name_elem.add_text(attr.name)

            if attr.data_size&.positive?
              data_elem = ea_elem.add_element("data")
              offset_elem = data_elem.add_element("offset")
              offset_elem.add_text(attr.data_offset.to_s)
              length_elem = data_elem.add_element("length")
              length_elem.add_text(attr.data_length.to_s)
              size_elem = data_elem.add_element("size")
              size_elem.add_text(attr.data_size.to_s)
            end
          end

          # Flags
          if entry.flags
            flags_elem = file_elem.add_element("flags")
            flags_elem.add_text(entry.flags)
          end

          # Nested files
          children = children_map[entry.name] || []
          children.each do |child|
            add_file_element(file_elem, child, children_map, entry.name)
          end
        end

        # Add timestamp element
        #
        # @param parent [REXML::Element] Parent element
        # @param name [String] Element name
        # @param time [Time] Time value
        def add_timestamp(parent, name, time)
          elem = parent.add_element(name)
          elem.add_text(time.to_f.to_s)
        end

        # Add checksum element
        #
        # @param parent [REXML::Element] Parent element
        # @param name [String] Element name
        # @param style [String] Checksum style
        # @param value [String] Checksum value
        def add_checksum(parent, name, style, value)
          return unless style && value

          elem = parent.add_element(name)
          elem.add_attribute("style", style)
          elem.add_text(value)
        end
      end
    end
  end
end

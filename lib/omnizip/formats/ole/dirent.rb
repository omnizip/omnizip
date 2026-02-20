# frozen_string_literal: true

require_relative "constants"
require_relative "types/variant"

module Omnizip
  module Formats
    module Ole
      # OLE directory entry (dirent)
      #
      # Represents a file or directory entry in an OLE compound document.
      # Each dirent is 128 bytes and contains metadata about the entry.
      class Dirent
        include Constants

        # Pack format for dirent structure
        PACK = "a64 v C C V3 a16 V a8 a8 V2 a4"

        # @return [String] 64-byte UTF-16LE name
        attr_accessor :name_utf16

        # @return [Integer] Name length in bytes
        attr_accessor :name_len

        # @return [Integer] Entry type (0=empty, 1=dir, 2=file, 5=root)
        attr_accessor :type_id

        # @return [Integer] Red-black tree color
        attr_accessor :colour

        # @return [Integer] Previous sibling index
        attr_accessor :prev

        # @return [Integer] Next sibling index
        attr_accessor :next

        # @return [Integer] First child index
        attr_accessor :child

        # @return [String] 16-byte CLSID
        attr_accessor :clsid

        # @return [Integer] Flags (for directories)
        attr_accessor :flags

        # @return [String] 8-byte creation time
        attr_accessor :create_time_str

        # @return [String] 8-byte modification time
        attr_accessor :modify_time_str

        # @return [Integer] First block of data
        attr_accessor :first_block

        # @return [Integer] Size in bytes
        attr_accessor :size

        # @return [String] 4-byte reserved
        attr_accessor :reserved

        # @return [Object] Parent OLE storage
        attr_reader :ole

        # @return [Symbol] Entry type (:empty, :dir, :file, :root)
        attr_reader :type

        # @return [String] Decoded entry name
        attr_reader :name

        # @return [Time, nil] Creation time
        attr_reader :create_time

        # @return [Time, nil] Modification time
        attr_reader :modify_time

        # @return [Array<Dirent>] Child entries (for directories)
        attr_reader :parent

        # @return [Integer, nil] Index in dirent array (used during loading)
        attr_accessor :idx

        # Parse dirent from binary data
        #
        # @param ole [Object] Parent OLE storage
        # @param data [String] 128-byte dirent data
        # @return [Dirent] Parsed dirent
        def self.parse(ole, data)
          dirent = new(ole)
          dirent.unpack(data)
          dirent
        end

        # Create new dirent with specified type and name
        #
        # @param ole [Object] Parent OLE storage
        # @param type [Symbol] Entry type (:file, :dir, :root)
        # @param name [String] Entry name
        # @return [Dirent] New dirent
        def self.create(ole, type:, name:)
          dirent = new(ole)
          dirent.type = type
          dirent.name = name
          dirent
        end

        # Initialize dirent
        #
        # @param ole [Object] Parent OLE storage
        def initialize(ole)
          @ole = ole
          @children = []
          @name_lookup = {}
          @parent = nil
          @idx = nil
          apply_defaults
        end

        # Apply default values
        def apply_defaults
          @name_utf16 = "\x00".b * 64
          @name_len = 2
          @type_id = 0
          @colour = 1 # black
          @prev = EOT
          @next = EOT
          @child = EOT
          @clsid = "\x00".b * 16
          @flags = 0
          @create_time_str = "\x00".b * 8
          @modify_time_str = "\x00".b * 8
          @first_block = EOC
          @size = 0
          @reserved = "\x00".b * 4
          @type = :empty
          @name = ""
        end

        # Set entry type
        #
        # @param value [Symbol] Type (:empty, :dir, :file, :root)
        def type=(value)
          @type = value
          @type_id = DIRENT_TYPES.invert[value] || 0

          if file?
            @children = nil
            @name_lookup = nil
          else
            @children ||= []
            @name_lookup ||= {}
          end
        end

        # Set entry name
        #
        # @param value [String] Entry name
        def name=(value)
          if @parent
            map = @parent.instance_variable_get(:@name_lookup)
            map&.delete(@name)
            map&.store(value, self)
          end
          @name = value
        end

        # Check if entry is a file
        #
        # @return [Boolean]
        def file?
          @type == :file
        end

        # Check if entry is a directory
        #
        # @return [Boolean]
        def dir?
          !file?
        end

        # Check if entry is root
        #
        # @return [Boolean]
        def root?
          @type == :root
        end

        # Check if entry is empty
        #
        # @return [Boolean]
        def empty?
          @type == :empty
        end

        # Unpack dirent from binary data
        #
        # @param data [String] 128-byte dirent data
        def unpack(data)
          values = data.unpack(PACK)
          @name_utf16 = values[0]
          @name_len = values[1]
          @type_id = values[2]
          @colour = values[3]
          @prev = values[4]
          @next = values[5]
          @child = values[6]
          @clsid = values[7]
          @flags = values[8]
          @create_time_str = values[9]
          @modify_time_str = values[10]
          @first_block = values[11]
          @size = values[12]
          @reserved = values[13]

          # Decode name from UTF-16LE
          # name_len includes the null terminator
          name_data = @name_utf16[0...@name_len] if @name_len.positive?
          @name = begin
            # Decode and strip null terminator
            decoded = name_data.dup.force_encoding(Encoding::UTF_16LE)
            # Remove trailing null character (UTF-16 null = 2 bytes)
            null_char = "\x00".encode(Encoding::UTF_16LE)
            decoded = decoded.chomp(null_char)
            decoded.encode(Encoding::UTF_8)
          rescue StandardError
            ""
          end

          # Decode type
          @type = DIRENT_TYPES[@type_id] || :empty

          # Decode timestamps for files
          if file?
            @create_time = begin
              Types::Variant.load(Types::Variant::VT_FILETIME, @create_time_str)
            rescue StandardError
              nil
            end
            @modify_time = begin
              Types::Variant.load(Types::Variant::VT_FILETIME, @modify_time_str)
            rescue StandardError
              nil
            end
            @children = nil
            @name_lookup = nil
          else
            @create_time = nil
            @modify_time = nil
            @children = []
            @name_lookup = {}
          end
        end

        # Pack dirent to binary data
        #
        # @return [String] 128-byte binary data
        def pack
          # Encode name to UTF-16LE with null terminator
          name_data = Types::Variant.dump(Types::Variant::VT_LPWSTR, @name)
          # Truncate to 62 bytes if needed (leaving room for null terminator)
          name_data = name_data[0, 62] + "\x00\x00".b if name_data.length > 62
          # Ensure null terminator exists
          name_data += "\x00\x00".b unless name_data.end_with?("\x00\x00".b)
          @name_len = name_data.length
          # Pad to 64 bytes total
          @name_utf16 = name_data + ("\x00".b * (64 - name_data.length))

          # Set type_id from type
          @type_id = DIRENT_TYPES.invert[@type] || 0

          # For directories, first_block should be EOT
          if dir? && !root?
            @first_block = EOT
          end

          # Encode timestamps for files
          if file?
            @create_time_str = Types::Variant.dump(Types::Variant::VT_FILETIME, @create_time) if @create_time
            @modify_time_str = Types::Variant.dump(Types::Variant::VT_FILETIME, @modify_time) if @modify_time
          else
            @create_time_str = "\x00".b * 8
            @modify_time_str = "\x00".b * 8
          end

          [
            @name_utf16, @name_len, @type_id, @colour,
            @prev, @next, @child, @clsid, @flags,
            @create_time_str, @modify_time_str,
            @first_block, @size, @reserved
          ].pack(PACK)
        end

        # Read file content
        #
        # @return [String] File content
        # @raise [Errno::EISDIR] If entry is a directory
        def read
          raise Errno::EISDIR unless file?

          bat = @ole.bat_for_size(@size)
          bat.read(@first_block, @size)
        end

        # Open stream for reading or writing
        #
        # @param mode [String] Open mode ('r' for read, 'w' for write)
        # @yield [RangesIOMigrateable] IO object
        # @return [RangesIOMigrateable]
        # @raise [Errno::EISDIR] If entry is a directory
        def open(mode = "r")
          raise Errno::EISDIR unless file?

          io = RangesIOMigrateable.new(self, mode)
          @modify_time = Time.now if io.respond_to?(:writeable?) && io.writeable?

          if block_given?
            begin
              yield io
            ensure
              io.close
            end
          else
            io
          end
        end

        # Lookup child by name
        #
        # @param name [String] Child name
        # @return [Dirent, nil] Child dirent
        def /(name)
          @name_lookup&.[](name)
        end
        alias [] :/

        # Add child entry
        #
        # @param child [Dirent] Child to add
        def <<(child)
          child.parent = self
          @name_lookup[child.name] = child if @name_lookup
          @children << child
        end

        # Set parent entry
        #
        # @param parent [Dirent, nil] Parent dirent
        def parent=(parent)
          @parent = parent
        end

        # Get all children
        #
        # @return [Array<Dirent>]
        def children
          @children || []
        end

        # Iterate over children
        #
        # @yield [Dirent]
        def each_child(&block)
          @children&.each(&block)
        end

        # Flatten tree to array for serialization
        #
        # @param dirents [Array<Dirent>] Output array
        # @return [Array<Dirent>]
        def flatten(dirents = [])
          @idx = dirents.length
          dirents << self

          if file?
            self.prev = EOT
            self.next = EOT
            self.child = EOT
          else
            children.each { |child| child.flatten(dirents) }
            self.child = self.class.flatten_helper(children)
          end

          dirents
        end

        # Helper to create balanced tree structure
        #
        # @param children [Array<Dirent>]
        # @return [Integer] Index of root of subtree
        def self.flatten_helper(children)
          return EOT if children.empty?

          i = children.length / 2
          this = children[i]
          this.prev = flatten_helper(children[0...i])
          this.next = flatten_helper(children[(i + 1)..])
          this.idx
        end

        # Inspect dirent
        #
        # @return [String]
        def inspect
          str = "#<Ole::Dirent:#{@name.inspect}"
          if file?
            str << " size=#{@size}"
          end
          "#{str}>"
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module Rpm
      # RPM tag definitions and value extraction
      #
      # Maps tag IDs to symbolic names and handles typed value extraction
      # from the header data blob.
      class Tag
        include Constants

        # Tag ID to name mapping (from rpm/rpmtag.h)
        TAG_IDS = {
          # Signature tags
          257 => :sigsize,
          261 => :sigmd5,
          262 => :siggpg,
          263 => :sigpgp5,
          267 => :dsaheader,
          268 => :rsaheader,
          269 => :sha1header,
          270 => :longsigsize,
          271 => :longarchivesize,

          # Header tags
          1000 => :name,
          1001 => :version,
          1002 => :release,
          1003 => :epoch,
          1004 => :summary,
          1005 => :description,
          1006 => :buildtime,
          1007 => :buildhost,
          1009 => :size,
          1010 => :distribution,
          1011 => :vendor,
          1014 => :license,
          1015 => :packager,
          1016 => :group,
          1020 => :url,
          1021 => :os,
          1022 => :arch,
          1023 => :prein,
          1024 => :postin,
          1025 => :preun,
          1026 => :postun,
          1027 => :oldfilenames,
          1028 => :filesizes,
          1029 => :filestates,
          1030 => :filemodes,
          1031 => :fileuids,
          1032 => :filegids,
          1033 => :filerdevs,
          1034 => :filemtimes,
          1035 => :filedigests,
          1036 => :filelinktos,
          1037 => :fileflags,
          1039 => :fileusername,
          1040 => :filegroupname,
          1044 => :sourcerpm,
          1046 => :archivesize,
          1047 => :providename,
          1048 => :requireflags,
          1049 => :requirename,
          1050 => :requireversion,
          1053 => :conflictflags,
          1054 => :conflictname,
          1055 => :conflictversion,
          1064 => :rpmversion,
          1090 => :obsoletename,
          1112 => :provideflags,
          1113 => :provideversion,
          1114 => :obsoleteflags,
          1115 => :obsoleteversion,
          1116 => :dirindexes,
          1117 => :basenames,
          1118 => :dirnames,
          1124 => :payloadformat,
          1125 => :payloadcompressor,
          1126 => :payloadflags,

          # Extended tags
          5000 => :filenames,
          5008 => :longfilesizes,
          5009 => :longsize,
          5013 => :evr,
          5014 => :nvr,
          5016 => :nevra,
          5019 => :epochnum,
        }.freeze

        # Type ID to name mapping
        TYPE_NAMES = {
          TYPE_NULL => :null,
          TYPE_CHAR => :char,
          TYPE_INT8 => :int8,
          TYPE_INT16 => :int16,
          TYPE_INT32 => :int32,
          TYPE_INT64 => :int64,
          TYPE_STRING => :string,
          TYPE_BINARY => :binary,
          TYPE_STRING_ARRAY => :string_array,
          TYPE_I18NSTRING => :i18nstring,
        }.freeze

        # @return [Integer] Tag ID
        attr_reader :tag_id

        # @return [Integer] Tag type
        attr_reader :type_id

        # @return [Integer] Offset into data blob
        attr_reader :offset

        # @return [Integer] Count of items
        attr_reader :count

        # @return [String] Data blob reference
        attr_reader :data

        # Initialize tag
        #
        # @param tag_id [Integer] Tag identifier
        # @param type_id [Integer] Type identifier
        # @param offset [Integer] Offset into data blob
        # @param count [Integer] Item count
        # @param data [String] Reference to data blob
        def initialize(tag_id, type_id, offset, count, data)
          @tag_id = tag_id
          @type_id = type_id
          @offset = offset
          @count = count
          @data = data
          @value = nil
        end

        # Get tag name
        #
        # @return [Symbol, Integer] Tag name or ID if unknown
        def name
          TAG_IDS.fetch(@tag_id, @tag_id)
        end

        # Get type name
        #
        # @return [Symbol, Integer] Type name or ID if unknown
        def type
          TYPE_NAMES.fetch(@type_id, @type_id)
        end

        # Get tag value (lazy extraction)
        #
        # @return [Object] Extracted value based on type
        def value
          return @value if @value

          @value = extract_value
        end

        private

        # Extract value based on type
        #
        # @return [Object] Extracted value
        def extract_value
          case type
          when :string, :i18nstring
            extract_string
          when :string_array
            extract_string_array
          when :binary
            extract_binary
          when :int8
            extract_int8
          when :int16
            extract_int16
          when :int32
            extract_int32
          when :int64
            extract_int64
          when :char
            extract_char
          else
            extract_binary
          end
        end

        def extract_string
          @data[@offset..]&.split("\0", 2)&.first || ""
        end

        def extract_string_array
          @data[@offset..].to_s.split("\0")[0...@count] || []
        end

        def extract_binary
          @data[@offset, @count] || ""
        end

        def extract_int8
          @data[@offset, @count].unpack("C" * @count)
        end

        def extract_int16
          @data[@offset, 2 * @count].unpack("n" * @count)
        end

        def extract_int32
          @data[@offset, 4 * @count].unpack("N" * @count)
        end

        def extract_int64
          values = []
          @count.times do |i|
            high, low = @data[@offset + (i * 8), 8].unpack("NN")
            values << ((high << 32) | low)
          end
          values
        end

        def extract_char
          @data[@offset, @count].unpack("a" * @count)
        end
      end
    end
  end
end

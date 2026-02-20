# frozen_string_literal: true

require_relative "constants"
require_relative "tag"

module Omnizip
  module Formats
    module Rpm
      # RPM header parser
      #
      # Parses RPM header structure including the 16-byte header header,
      # tag entries, and data blob. Used for both signature and main headers.
      class Header
        include Constants

        # @return [String] 8-byte header magic
        attr_reader :magic

        # @return [Integer] Number of tag entries
        attr_reader :entry_count

        # @return [Integer] Data blob length
        attr_reader :data_length

        # @return [Array<Tag>] Parsed tags
        attr_reader :tags

        # @return [Integer] Total header length
        attr_reader :length

        # Parse header from IO
        #
        # @param io [IO] Input stream positioned at header
        # @return [Header] Parsed header object
        # @raise [ArgumentError] If magic is invalid
        def self.parse(io)
          new.tap do |header|
            header.send(:parse!, io)
          end
        end

        # Get tag value by name
        #
        # @param name [Symbol] Tag name
        # @return [Object, nil] Tag value or nil if not found
        def [](name)
          tag = find_tag(name)
          tag&.value
        end

        # Find tag by name
        #
        # @param name [Symbol] Tag name
        # @return [Tag, nil] Tag object or nil
        def find_tag(name)
          @tags.find { |t| t.name == name }
        end

        # Get all tags as hash
        #
        # @return [Hash] Tag names to values
        def to_h
          @tags.each_with_object({}) do |tag, hash|
            hash[tag.name] = tag.value
          end
        end

        # Validate header
        #
        # @raise [ArgumentError] If validation fails
        def validate!
          unless @magic == HEADER_MAGIC
            raise ArgumentError,
                  "Invalid header magic: #{@magic.inspect}"
          end
        end

        private

        def parse!(io)
          # Read header header (16 bytes)
          header_data = io.read(HEADER_HEADER_SIZE)
          raise ArgumentError, "Failed to read RPM header" unless header_data

          @magic = header_data[0, 8]
          @entry_count = header_data[8, 4].unpack1("N")
          @data_length = header_data[12, 4].unpack1("N")

          validate!

          # Read tag entries
          tag_data_size = @entry_count * TAG_ENTRY_SIZE
          tag_entries_data = io.read(tag_data_size)

          # Read data blob
          data_blob = io.read(@data_length)

          # Parse tags
          @tags = []
          @entry_count.times do |i|
            offset = i * TAG_ENTRY_SIZE
            entry = tag_entries_data[offset, TAG_ENTRY_SIZE].unpack("NNNN")

            tag = Tag.new(entry[0], entry[1], entry[2], entry[3], data_blob)
            @tags << tag
          end

          @length = HEADER_HEADER_SIZE + tag_data_size + @data_length
        end
      end
    end
  end
end

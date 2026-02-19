# frozen_string_literal: true

require "stringio"
require_relative "../xz_impl/constants"
require_relative "../xz_impl/stream_header"
require_relative "../xz_impl/stream_footer"
require_relative "../xz_impl/block_encoder"
require_relative "../xz_impl/index_encoder"
require_relative "../../error"

module Omnizip
  module Formats
    module XzFormat
      # XZ Stream encoder
      # Orchestrates the complete XZ stream creation
      # Based on XZ Utils stream_encoder.c
      class StreamEncoder
        include Omnizip::Formats::XzConst

        def initialize(check_type: CHECK_CRC64, dict_size: 64 * 1024 * 1024)
          @check_type = check_type
          @dict_size = dict_size
          @index = IndexEncoder.new
        end

        # Encode data into XZ format
        # @param input [String, IO] Input data to compress
        # @return [String] XZ-formatted compressed data
        def encode(input)
          output = StringIO.new
          output.set_encoding(Encoding::BINARY)

          # Read input data
          input_data = input.respond_to?(:read) ? input.read : input.to_s
          input_data = input_data.dup.force_encoding(Encoding::BINARY)

          # 1. Write Stream Header
          header = StreamHeader.new(check_type: @check_type)
          output.write(header.encode)

          # 2. Encode and write Block(s)
          encode_blocks(input_data, output)

          # 3. Write Index
          index_data = @index.encode
          output.write(index_data)

          # 4. Write Stream Footer
          footer = StreamFooter.new(
            check_type: @check_type,
            backward_size: @index.size,
          )
          output.write(footer.encode)

          output.string
        end

        private

        def encode_blocks(data, output)
          # XZ Utils behavior: If input is empty, don't create any blocks
          # The stream will consist of just: Stream Header + Index + Stream Footer
          return if data.empty? || data.nil?

          # For now, encode entire data as single block
          # TODO: Support multi-block encoding for large files

          # Include block sizes for XZ Utils compatibility
          # This ensures that XZ Utils can properly decode the files
          block_encoder = BlockEncoder.new(
            check_type: @check_type,
            dict_size: @dict_size,
            include_block_sizes: true, # Include size fields for compatibility
          )

          block = block_encoder.encode_block(data)

          # Write block header
          output.write(block[:header])

          # Write compressed data
          output.write(block[:data])

          # Write padding
          output.write(block[:padding])

          # Write check value
          output.write(block[:check])

          # Add to index
          @index.add_record(
            block_encoder.unpadded_size,
            block_encoder.uncompressed_size,
          )
        end
      end
    end
  end
end

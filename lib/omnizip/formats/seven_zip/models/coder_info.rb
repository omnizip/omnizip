# frozen_string_literal: true

module Omnizip
  module Formats
    module SevenZip
      module Models
        # Represents a coder (compression algorithm or filter) in .7z format
        # Each coder has a method ID, properties, and input/output stream info
        class CoderInfo
          attr_accessor :method_id, :num_in_streams, :num_out_streams,
                        :properties

          # Initialize coder info
          #
          # @param method_id [Integer] Compression/filter method ID
          # @param num_in_streams [Integer] Number of input streams
          # @param num_out_streams [Integer] Number of output streams
          # @param properties [String] Binary properties data
          def initialize(method_id: 0, num_in_streams: 1,
                         num_out_streams: 1, properties: "".b)
            @method_id = method_id
            @num_in_streams = num_in_streams
            @num_out_streams = num_out_streams
            @properties = properties
          end
        end
      end
    end
  end
end

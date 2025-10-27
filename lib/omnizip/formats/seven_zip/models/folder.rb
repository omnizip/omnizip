# frozen_string_literal: true

require_relative "coder_info"

module Omnizip
  module Formats
    module SevenZip
      module Models
        # Represents a folder (compression group) in .7z format
        # Contains coder chain and binding information
        class Folder
          attr_accessor :coders, :bind_pairs, :pack_stream_indices,
                        :unpack_sizes, :unpack_crc

          # Initialize folder
          #
          # @param coders [Array<CoderInfo>] Array of coders
          # @param bind_pairs [Array<Array<Integer>>] Stream bindings
          # @param pack_stream_indices [Array<Integer>] Pack stream indices
          def initialize
            @coders = []
            @bind_pairs = []
            @pack_stream_indices = []
            @unpack_sizes = []
            @unpack_crc = nil
          end

          # Get number of coders in folder
          #
          # @return [Integer] Coder count
          def num_coders
            @coders.size
          end

          # Get total number of output streams
          #
          # @return [Integer] Output stream count
          def num_out_streams
            @coders.sum(&:num_out_streams)
          end

          # Get total number of input streams
          #
          # @return [Integer] Input stream count
          def num_in_streams
            @coders.sum(&:num_in_streams)
          end
        end
      end
    end
  end
end

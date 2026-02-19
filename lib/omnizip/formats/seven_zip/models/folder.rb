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

          # Get uncompressed size of folder's final output stream
          # Finds the output stream that is not bound as input
          #
          # @return [Integer] Uncompressed size
          def uncompressed_size
            # Find which output stream is the final one (not bound as input)
            n = num_out_streams - 1
            while n >= 0
              # Check if this output is bound as input
              bound = @bind_pairs.any? { |pair| pair[1] == n }
              return @unpack_sizes[n] || 0 unless bound

              n -= 1
            end
            0
          end
        end
      end
    end
  end
end

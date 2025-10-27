# frozen_string_literal: true

module Omnizip
  module Formats
    module SevenZip
      module Models
        # Represents stream information in .7z format
        # Contains packed streams, folders, and unpacked stream metadata
        class StreamInfo
          attr_accessor :pack_pos, :pack_sizes, :pack_crcs, :folders,
                        :num_unpack_streams_in_folders,
                        :unpack_sizes, :digests

          # Initialize stream info
          def initialize
            @pack_pos = 0
            @pack_sizes = []
            @pack_crcs = []
            @folders = []
            @num_unpack_streams_in_folders = []
            @unpack_sizes = []
            @digests = []
          end

          # Get total number of folders
          #
          # @return [Integer] Folder count
          def num_folders
            @folders.size
          end

          # Get total number of pack streams
          #
          # @return [Integer] Pack stream count
          def num_pack_streams
            @pack_sizes.size
          end
        end
      end
    end
  end
end

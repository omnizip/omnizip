# frozen_string_literal: true

begin
  require "lutaml/model"
rescue LoadError, ArgumentError
  # lutaml-model not available, using simple classes
end

module Omnizip
  module Formats
    module Rar
      module Rar5
        module Models
          # Solid compression options
          #
          # This model configures solid compression behavior, including
          # whether to enable solid mode and block size limits.
          #
          # @example Enable solid compression
          #   options = SolidOptions.new(enabled: true)
          #
          # @example Configure solid block size
          #   options = SolidOptions.new(enabled: true, max_block_size: 100 * 1024 * 1024)
          class SolidOptions < Lutaml::Model::Serializable
            # Enable solid compression (default: false)
            attribute :enabled, :boolean, default: false

            # Maximum solid block size in bytes (default: unlimited)
            # When set, files are grouped into blocks not exceeding this size
            attribute :max_block_size, :integer, default: nil

            # Whether to split by file extension (default: false)
            # When true, files with different extensions use separate solid blocks
            attribute :split_by_extension, :boolean, default: false

            # Validate options
            #
            # @raise [ArgumentError] if max_block_size is too small
            def validate!
              if max_block_size && max_block_size < 1_048_576 # 1 MB minimum
                raise ArgumentError, "Solid block size must be at least 1 MB"
              end
            end

            # Check if solid compression is enabled
            #
            # @return [Boolean] true if enabled
            def enabled?
              enabled == true
            end

            # Check if block size is limited
            #
            # @return [Boolean] true if max_block_size set
            def block_size_limited?
              !max_block_size.nil?
            end
          end
        end
      end
    end
  end
end

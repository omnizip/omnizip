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
          # Volume options for multi-volume archives
          #
          # This model configures split archive behavior, including
          # maximum volume size and naming convention.
          #
          # @example Create with default options
          #   options = VolumeOptions.new
          #   options.max_volume_size # => 104857600 (100 MB)
          #
          # @example Create with custom size
          #   options = VolumeOptions.new(max_volume_size: 10 * 1024 * 1024)
          #   options.max_volume_size # => 10485760 (10 MB)
          class VolumeOptions < Lutaml::Model::Serializable
            # Maximum size per volume in bytes (default: 100 MB)
            attribute :max_volume_size, :integer, default: 104_857_600

            # Volume naming pattern (default: 'part')
            # Results in: archive.part1.rar, archive.part2.rar, etc.
            attribute :volume_naming, :string, default: "part"

            # Validate options
            #
            # @raise [ArgumentError] if max_volume_size is too small
            def validate!
              if max_volume_size < 65_536 # 64 KB minimum
                raise ArgumentError, "Volume size must be at least 64 KB"
              end
            end

            # Parse human-readable size string
            #
            # @param size_str [String] Size with suffix (e.g., "10M", "1G")
            # @return [Integer] Size in bytes
            def self.parse_size(size_str)
              return size_str if size_str.is_a?(Integer)

              match = size_str.match(/^(\d+(?:\.\d+)?)\s*([KMGT])?$/i)
              unless match
                raise ArgumentError,
                      "Invalid size format: #{size_str}"
              end

              value = match[1].to_f
              suffix = match[2]&.upcase

              multiplier = case suffix
                           when "K" then 1024
                           when "M" then 1024**2
                           when "G" then 1024**3
                           when "T" then 1024**4
                           else 1
                           end

              (value * multiplier).to_i
            end
          end
        end
      end
    end
  end
end

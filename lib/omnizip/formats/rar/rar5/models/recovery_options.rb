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
          # Recovery (PAR2) options for RAR5 archives
          #
          # This model configures PAR2 parity file generation for error
          # correction and recovery of corrupted or missing archive data.
          #
          # @example Enable recovery with default settings
          #   options = RecoveryOptions.new(enabled: true)
          #
          # @example Custom redundancy percentage
          #   options = RecoveryOptions.new(
          #     enabled: true,
          #     redundancy: 10  # 10% redundancy
          #   )
          class RecoveryOptions < Lutaml::Model::Serializable
            # Enable PAR2 recovery (default: false)
            attribute :enabled, :boolean, default: false

            # Redundancy percentage (0-100, default: 5)
            attribute :redundancy, :integer, default: 5

            # Block size for PAR2 (default: 16384)
            attribute :block_size, :integer, default: 16_384

            # Validate options
            #
            # @raise [ArgumentError] If validation fails
            def validate!
              if redundancy.negative? || redundancy > 100
                raise ArgumentError,
                      "Redundancy must be 0-100, got #{redundancy}"
              end

              if block_size <= 0 || (block_size % 4) != 0
                raise ArgumentError,
                      "Block size must be positive and divisible by 4"
              end
            end

            # Check if recovery is enabled
            #
            # @return [Boolean] true if enabled
            def enabled?
              enabled == true
            end
          end
        end
      end
    end
  end
end

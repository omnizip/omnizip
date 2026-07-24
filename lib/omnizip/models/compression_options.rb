# frozen_string_literal: true


require "omnizip"
require "lutaml/model"
require "json"

module Omnizip
  module Models
    # Model representing compression operation options.
    #
    # Serialized via lutaml-model — callers should not write hand-rolled
    # +to_h+ / +to_json+ / +from_json+ on this class. The framework
    # provides +#to_hash+, +#to_json+, and +.from_hash+ / +.from_json+
    # automatically from the +attribute+ declarations below.
    class CompressionOptions < Lutaml::Model::Serializable
      attribute :level, :integer, default: 5
      attribute :dictionary_size, :integer
      attribute :num_fast_bytes, :integer
      attribute :match_finder, :string
      attribute :num_threads, :integer, default: 1
      attribute :solid, :boolean, default: false
      attribute :buffer_size, :integer, default: 65_536

      # JSON / hash mappings (1:1, no renames needed).
      json do
        map :level, to: :level
        map :dictionary_size, to: :dictionary_size
        map :num_fast_bytes, to: :num_fast_bytes
        map :match_finder, to: :match_finder
        map :num_threads, to: :num_threads
        map :solid, to: :solid
        map :buffer_size, to: :buffer_size
      end

      # Apply a hash of attributes. Only keys declared as +attribute+s
      # above are applied; unknown keys are silently ignored.
      #
      # @param attributes [Hash{Symbol=>Object}]
      # @return [self]
      def apply(attributes)
        self.class.attributes.each do |attr|
          name = attr.name
          public_send("#{name}=", attributes[name]) if attributes.key?(name)
        end
        self
      end

      # Validate that all set values are within their type's domain.
      #
      # @raise [ArgumentError] if any value is invalid
      # @return [Boolean] true if valid
      def validate!
        raise ArgumentError, "level must be 0-9" unless (0..9).cover?(level)

        true
      end
    end
  end
end

# frozen_string_literal: true

require "lutaml/model"

module Omnizip
  module Models
    # Metadata describing a compression algorithm.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    class AlgorithmMetadata < Lutaml::Model::Serializable
      include AttributeApply

      attribute :name, :string
      attribute :description, :string
      attribute :version, :string
      attribute :author, :string
      attribute :max_compression_level, :integer
      attribute :min_compression_level, :integer
      attribute :default_compression_level, :integer
      attribute :supports_streaming, :boolean, default: false
      attribute :supports_multithreading, :boolean, default: false

      json do
        map :name, to: :name
        map :description, to: :description
        map :version, to: :version
        map :author, to: :author
        map :max_compression_level, to: :max_compression_level
        map :min_compression_level, to: :min_compression_level
        map :default_compression_level, to: :default_compression_level
        map :supports_streaming, to: :supports_streaming
        map :supports_multithreading, to: :supports_multithreading
      end

      # Apply a hash of attributes (whitelisted to declared attributes).
      #
      # @param attributes [Hash{Symbol=>Object}]
      # @return [self]
    end
  end
end

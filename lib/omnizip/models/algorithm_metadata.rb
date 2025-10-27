# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

require "lutaml/model"

module Omnizip
  module Models
    # Model representing metadata about a compression algorithm.
    #
    # This class encapsulates information about a compression algorithm,
    # including its name, description, version, and capabilities.
    class AlgorithmMetadata < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :description, :string
      attribute :version, :string
      attribute :author, :string
      attribute :max_compression_level, :integer
      attribute :min_compression_level, :integer
      attribute :default_compression_level, :integer
      attribute :supports_streaming, :boolean, default: -> { false }
      attribute :supports_multithreading, :boolean, default: -> { false }

      json do
        map "name", to: :name
        map "description", to: :description
        map "version", to: :version
        map "author", to: :author
        map "max_compression_level", to: :max_compression_level
        map "min_compression_level", to: :min_compression_level
        map "default_compression_level", to: :default_compression_level
        map "supports_streaming", to: :supports_streaming
        map "supports_multithreading", to: :supports_multithreading
      end
    end
  end
end

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
    # Model representing compression operation options.
    #
    # This class encapsulates configuration options for compression
    # operations, including compression level, threading, and buffer sizes.
    class CompressionOptions < Lutaml::Model::Serializable
      attribute :level, :integer, default: -> { 5 }
      attribute :dictionary_size, :integer
      attribute :num_fast_bytes, :integer
      attribute :match_finder, :string
      attribute :num_threads, :integer, default: -> { 1 }
      attribute :solid, :boolean, default: -> { false }
      attribute :buffer_size, :integer, default: -> { 65_536 }

      json do
        map "level", to: :level
        map "dictionary_size", to: :dictionary_size
        map "num_fast_bytes", to: :num_fast_bytes
        map "match_finder", to: :match_finder
        map "num_threads", to: :num_threads
        map "solid", to: :solid
        map "buffer_size", to: :buffer_size
      end
    end
  end
end

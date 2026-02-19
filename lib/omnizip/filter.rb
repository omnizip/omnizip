# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

module Omnizip
  # Abstract base class for all preprocessing filters
  #
  # Filters are reversible transformations applied to data before
  # compression to improve compression ratios. This class defines the
  # interface that all filter implementations must follow.
  #
  # The key innovation is format-aware ID resolution: different formats
  # (7z, XZ) use different IDs for the same filter. This class provides the
  # id_for_format(format) method to handle this mapping.
  #
  # @abstract Subclasses must implement encode, decode, metadata
  #
  # @example Create a custom filter
  #   class MyFilter < Filter
  #     def initialize(architecture:)
  #       super(architecture: architecture, name: "MyFilter")
  #     end
  #
  #     def id_for_format(format)
  #       format == :xz ? 0x04 : 0x03
  #     end
  #
  #     def encode(data, position = 0)
  #       # encoding logic
  #     end
  #
  #     def decode(data, position = 0)
  #       # decoding logic
  #     end
  #
  #     def self.metadata
  #       { name: "MyFilter", description: "..." }
  #     end
  #   end
  class Filter
    # @return [Symbol] Architecture identifier (:x86, :arm, :arm64, :powerpc, :ia64, :sparc)
    attr_reader :architecture

    # @return [String] Human-readable filter name
    attr_reader :name

    # Initialize filter
    #
    # @param architecture [Symbol] Target architecture
    # @param name [String] Human-readable name
    def initialize(architecture:, name: "Unknown")
      @architecture = architecture
      @name = name
    end

    # Get filter ID for specific format
    #
    # This is the KEY METHOD that solves the filter ID mapping problem.
    # Different formats (7z, XZ) use different IDs for the same filter.
    #
    # @param format [Symbol] Format identifier (:seven_zip, :xz)
    # @return [Integer] Format-specific filter ID
    # @raise [NotImplementedError] Subclass must implement
    #
    # @example Get XZ format ID for BCJ filter
    #   bcj.id_for_format(:xz)  # => 0x04
    #
    # @example Get 7z format ID for BCJ filter
    #   bcj.id_for_format(:seven_zip)  # => 0x03030103
    def id_for_format(format)
      raise NotImplementedError,
            "#{self.class} must implement #id_for_format(format)"
    end

    # Encode (preprocess) data for compression
    #
    # Transforms data to make it more compressible. The transformation
    # must be reversible - decode(encode(data)) == data.
    #
    # @param data [String] Binary data to encode
    # @param position [Integer] Current stream position (default: 0)
    # @return [String] Encoded binary data
    # @raise [NotImplementedError] Subclass must implement
    def encode(data, position = 0)
      raise NotImplementedError,
            "#{self.class} must implement #encode(data, position)"
    end

    # Decode (postprocess) data after decompression
    #
    # Reverses the encoding transformation, restoring original data.
    #
    # @param data [String] Binary data to decode
    # @param position [Integer] Current stream position (default: 0)
    # @return [String] Decoded binary data
    # @raise [NotImplementedError] Subclass must implement
    def decode(data, position = 0)
      raise NotImplementedError,
            "#{self.class} must implement #decode(data, position)"
    end

    class << self
      # Get metadata about this filter
      #
      # @return [Hash] Filter metadata
      # @option metadata [String] :name Human-readable name
      # @option metadata [String] :description Filter description
      # @option metadata [Array<Symbol>] :supported_archs Supported architectures
      # @raise [NotImplementedError] Subclass must implement
      #
      # @example Get BCJ filter metadata
      #   Omnizip::Filters::BCJ.metadata
      #   # => { name: "BCJ", description: "...", supported_archs: [:x86, :arm, ...] }
      def metadata
        raise NotImplementedError,
              "#{self} must implement .metadata"
      end
    end
  end
end

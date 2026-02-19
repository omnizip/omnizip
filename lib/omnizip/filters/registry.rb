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

require_relative "filter_base"
require_relative "bcj_x86"
require_relative "bcj_arm"
require_relative "bcj_arm64"
require_relative "bcj_ia64"
require_relative "bcj_ppc"
require_relative "bcj_sparc"
require_relative "bcj2"
require_relative "delta"
require_relative "bcj" # Unified BCJ filter (Task 2)
require_relative "../filter_registry"

module Omnizip
  module Filters
    # Registry for auto-registering all preprocessing filters.
    #
    # This module centralizes filter registration, ensuring all filters
    # are properly registered with their supported formats.
    module Registry
      # Register all BCJ filters with appropriate format support.
      #
      # BCJ filters are architecture-specific filters for executable code.
      # XZ format supports a subset of architectures (no ARM64),
      # while 7z supports all.
      #
      # @return [void]
      def self.register_bcj_filters
        # Individual BCJ architecture filters (use hyphens to match existing convention)
        register_bcj_filter(:'bcj-x86', BcjX86, architecture: :x86)
        register_bcj_filter(:'bcj-arm', BcjArm, architecture: :arm)
        register_bcj_filter(:'bcj-arm64', BcjArm64, architecture: :arm64,
                                                    xz_supported: false)
        register_bcj_filter(:'bcj-ia64', BcjIa64, architecture: :ia64)
        register_bcj_filter(:'bcj-ppc', BcjPpc, architecture: :powerpc)
        register_bcj_filter(:'bcj-sparc', BcjSparc, architecture: :sparc)

        # Unified BCJ filter (Task 2) - supports all architectures
        # Note: We register it as 'bcj' without architecture suffix
        Omnizip::FilterRegistry.register_with_formats(
          :bcj,
          Omnizip::Filters::BCJ,
          formats: [:seven_zip], # Only 7z for now (uses architecture parameter)
        )
      end

      # Register a BCJ filter with format support.
      #
      # @param name [Symbol] Filter name identifier
      # @param filter_class [Class] Filter class to register
      # @param architecture [Symbol] Target architecture
      # @param xz_supported [Boolean] Whether XZ format supports this architecture
      # @return [void]
      def self.register_bcj_filter(name, filter_class, architecture:,
xz_supported: true)
        formats = [:seven_zip]
        formats << :xz if xz_supported
        Omnizip::FilterRegistry.register_with_formats(name, filter_class,
                                                      formats: formats)
      end

      # Register Delta filter.
      #
      # Delta filter is supported by both XZ and 7z formats.
      #
      # @return [void]
      def self.register_delta_filter
        Omnizip::FilterRegistry.register_with_formats(
          :delta,
          Delta,
          formats: %i[seven_zip xz],
        )
      end

      # Register BCJ2 filter.
      #
      # BCJ2 is a 4-stream variant of BCJ, primarily used by 7z.
      # XZ does not support BCJ2.
      #
      # @return [void]
      def self.register_bcj2_filter
        Omnizip::FilterRegistry.register_with_formats(
          :bcj2,
          Bcj2,
          formats: [:seven_zip], # Only 7z supports BCJ2
        )
      end

      # Register all filters.
      #
      # This method registers all available filters with their
      # appropriate format support. Call this during application
      # initialization to ensure all filters are available.
      #
      # @return [void]
      def self.register_all
        register_bcj_filters
        register_delta_filter
        register_bcj2_filter
      end
    end
  end
end

# Auto-register all filters on load
Omnizip::Filters::Registry.register_all

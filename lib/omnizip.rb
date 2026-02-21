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

# Core version and errors
require_relative "omnizip/version"
require_relative "omnizip/error"

# Core registries (required before algorithms/formats)
require_relative "omnizip/algorithm"
require_relative "omnizip/algorithm_registry"
require_relative "omnizip/format_registry"
require_relative "omnizip/optimization_registry"
require_relative "omnizip/checksum_registry"
require_relative "omnizip/filter_registry"

# Base classes for algorithms and filters
require_relative "omnizip/algorithms/ppmd_base"
require_relative "omnizip/filter"
require_relative "omnizip/filter_pipeline"
require_relative "omnizip/filters/filter_base"
require_relative "omnizip/checksums/crc_base"

module Omnizip
  # Models - autoloaded for lazy loading
  module Models
    autoload :AlgorithmMetadata, "omnizip/models/algorithm_metadata"
    autoload :CompressionOptions, "omnizip/models/compression_options"
    autoload :PerformanceResult, "omnizip/models/performance_result"
    autoload :ProfileReport, "omnizip/models/profile_report"
    autoload :OptimizationSuggestion, "omnizip/models/optimization_suggestion"
    autoload :ProgressOptions, "omnizip/models/progress_options"
    autoload :EtaResult, "omnizip/models/eta_result"
    autoload :FilterConfig, "omnizip/models/filter_config"
    autoload :FilterChain, "omnizip/models/filter_chain"
    autoload :ParallelOptions, "omnizip/models/parallel_options"
  end
end

# Module files with autoload declarations for their sub-components
require_relative "omnizip/io"
require_relative "omnizip/crypto"
require_relative "omnizip/formats"
require_relative "omnizip/zip"

# Feature modules - autoloaded from top level
module Omnizip
  autoload :Buffer, "omnizip/buffer"
  autoload :Pipe, "omnizip/pipe"
  autoload :Chunked, "omnizip/chunked"
  autoload :Temp, "omnizip/temp"
  autoload :FileType, "omnizip/file_type"
  autoload :Profile, "omnizip/profile"
  autoload :ETA, "omnizip/eta"
  autoload :Progress, "omnizip/progress"
  autoload :Metadata, "omnizip/metadata"
  autoload :Password, "omnizip/password"
  autoload :Converter, "omnizip/converter"
  autoload :LinkHandler, "omnizip/link_handler"
  autoload :Parity, "omnizip/parity"
  autoload :Platform, "omnizip/platform"
  autoload :Profiler, "omnizip/profiler"
end

# Convenience methods must be explicitly required (not autoloaded)
# because they extend Omnizip with class methods via `extend Convenience`
require_relative "omnizip/convenience"

# Algorithms (with registration - must be required explicitly)
require_relative "omnizip/algorithms/lzma"
require_relative "omnizip/algorithms/lzma2"
require_relative "omnizip/algorithms/ppmd7"
require_relative "omnizip/algorithms/ppmd8"
require_relative "omnizip/algorithms/bzip2"
require_relative "omnizip/algorithms/deflate"
require_relative "omnizip/algorithms/deflate64"
require_relative "omnizip/algorithms/zstandard"

# Filter implementations (with registration)
require_relative "omnizip/filters/bcj"
require_relative "omnizip/filters/bcj_x86"
require_relative "omnizip/filters/bcj2"
require_relative "omnizip/filters/bcj_arm"
require_relative "omnizip/filters/bcj_arm64"
require_relative "omnizip/filters/bcj_ppc"
require_relative "omnizip/filters/bcj_sparc"
require_relative "omnizip/filters/bcj_ia64"
require_relative "omnizip/filters/delta"
require_relative "omnizip/filters/registry"

# Checksum implementations (with registration)
require_relative "omnizip/checksums/crc32"
require_relative "omnizip/checksums/crc64"

# Register checksum algorithms
Omnizip::ChecksumRegistry.register(:crc32, Omnizip::Checksums::Crc32)
Omnizip::ChecksumRegistry.register(:crc64, Omnizip::Checksums::Crc64)

# Archive formats (with registration - must be required explicitly)
require_relative "omnizip/formats/seven_zip"
require_relative "omnizip/formats/zip"
require_relative "omnizip/formats/rar"
require_relative "omnizip/formats/tar"
require_relative "omnizip/formats/gzip"
require_relative "omnizip/formats/bzip2_file"
require_relative "omnizip/formats/xz"

# Platform-specific features
require_relative "omnizip/platform/ntfs_streams"

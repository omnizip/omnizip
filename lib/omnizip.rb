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

module Omnizip
  # Core version - autoloaded
  autoload :VERSION, "omnizip/version"

  # Error classes - autoloaded
  autoload :Error, "omnizip/error"
  autoload :CompressionError, "omnizip/error"
  autoload :DecompressionError, "omnizip/error"
  autoload :AlgorithmNotFoundError, "omnizip/error"
  autoload :UnknownAlgorithmError, "omnizip/error"
  autoload :UnsupportedFormatError, "omnizip/error"
  autoload :FormatError, "omnizip/error"
  autoload :InvalidArchiveError, "omnizip/error"
  autoload :IOError, "omnizip/error"
  autoload :ChecksumError, "omnizip/error"
  autoload :OptimizationNotFound, "omnizip/error"
  autoload :ProgressError, "omnizip/error"
  autoload :ETAError, "omnizip/error"
  autoload :NotLicensedError, "omnizip/error"
  autoload :RarNotAvailableError, "omnizip/error"

  # Core registries
  autoload :Algorithm, "omnizip/algorithm"
  autoload :AlgorithmRegistry, "omnizip/algorithm_registry"
  autoload :FormatRegistry, "omnizip/format_registry"
  autoload :OptimizationRegistry, "omnizip/optimization_registry"
  autoload :ChecksumRegistry, "omnizip/checksum_registry"
  autoload :FilterRegistry, "omnizip/filter_registry"

  # Base classes
  autoload :Filter, "omnizip/filter"
  autoload :FilterPipeline, "omnizip/filter_pipeline"

  # Feature modules
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
  autoload :Commands, "omnizip/commands"

  # Sub-module files
  autoload :IO, "omnizip/io"
  autoload :Crypto, "omnizip/crypto"
  autoload :Formats, "omnizip/formats"
  autoload :Zip, "omnizip/zip"
end

# Models module with autoloaded classes
module Omnizip
  module Models
    autoload :AlgorithmMetadata, "omnizip/models/algorithm_metadata"
    autoload :CompressionOptions, "omnizip/models/compression_options"
    autoload :PerformanceResult, "omnizip/models/performance_result"
    autoload :ProfileReport, "omnizip/models/profile_report"
    autoload :OptimizationSuggestion, "omnizip/models/optimization_suggestion"
    autoload :ProgressOptions, "omnizip/models/progress_options"
    autoload :ETAResult, "omnizip/models/eta_result"
    autoload :FilterConfig, "omnizip/models/filter_config"
    autoload :FilterChain, "omnizip/models/filter_chain"
    autoload :ParallelOptions, "omnizip/models/parallel_options"
    autoload :SplitOptions, "omnizip/models/split_options"
    autoload :ConversionOptions, "omnizip/models/conversion_options"
    autoload :ConversionResult, "omnizip/models/conversion_result"
    autoload :ExtractionRule, "omnizip/models/extraction_rule"
    autoload :MatchResult, "omnizip/models/match_result"
  end
end

# Algorithms module with autoloaded classes
module Omnizip
  module Algorithms
    autoload :PPMdBase, "omnizip/algorithms/ppmd_base"
    autoload :LZMA, "omnizip/algorithms/lzma"
    autoload :LZMA2, "omnizip/algorithms/lzma2"
    autoload :LZMA2Encoder, "omnizip/algorithms/lzma2/encoder"
    autoload :LZMA2XzEncoderAdapter,
             "omnizip/algorithms/lzma2/xz_encoder_adapter"
    autoload :LZMA2Chunk, "omnizip/algorithms/lzma2/lzma2_chunk"
    autoload :PPMd7, "omnizip/algorithms/ppmd7"
    autoload :PPMd8, "omnizip/algorithms/ppmd8"
    autoload :BZip2, "omnizip/algorithms/bzip2"
    autoload :Deflate, "omnizip/algorithms/deflate"
    autoload :Deflate64, "omnizip/algorithms/deflate64"
    autoload :Zstandard, "omnizip/algorithms/zstandard"
  end
end

# Filters module with autoloaded classes
module Omnizip
  module Filters
    autoload :FilterBase, "omnizip/filters/filter_base"
    autoload :BCJ, "omnizip/filters/bcj"
    autoload :BCJx86, "omnizip/filters/bcj_x86"
    autoload :BCJ2, "omnizip/filters/bcj2"
    autoload :BCJArm, "omnizip/filters/bcj_arm"
    autoload :BCJArm64, "omnizip/filters/bcj_arm64"
    autoload :BCJPpc, "omnizip/filters/bcj_ppc"
    autoload :BCJSparc, "omnizip/filters/bcj_sparc"
    autoload :BCJIa64, "omnizip/filters/bcj_ia64"
    autoload :Delta, "omnizip/filters/delta"
    autoload :Registry, "omnizip/filters/registry"
  end
end

# Checksums module with autoloaded classes
module Omnizip
  module Checksums
    autoload :CrcBase, "omnizip/checksums/crc_base"
    autoload :Crc32, "omnizip/checksums/crc32"
    autoload :Crc64, "omnizip/checksums/crc64"
  end
end

# Formats module with autoloaded classes
module Omnizip
  module Formats
    autoload :SevenZip, "omnizip/formats/seven_zip"
    autoload :Zip, "omnizip/formats/zip"
    autoload :Rar, "omnizip/formats/rar"
    autoload :Tar, "omnizip/formats/tar"
    autoload :Gzip, "omnizip/formats/gzip"
    autoload :Bzip2File, "omnizip/formats/bzip2_file"
    autoload :Xz, "omnizip/formats/xz"
  end
end

# Platform-specific features
module Omnizip
  module Platform
    autoload :NtfsStreams, "omnizip/platform/ntfs_streams"
  end

  # Implementations module with autoloaded classes
  module Implementations
    autoload :SevenZip, "omnizip/implementations/seven_zip"
    autoload :XZUtils, "omnizip/implementations/xz_utils"
    module SevenZip
      module LZMA
        autoload :StateMachine,
                 "omnizip/implementations/seven_zip/lzma/state_machine"
        autoload :MatchFinder,
                 "omnizip/implementations/seven_zip/lzma/match_finder"
        autoload :Encoder, "omnizip/implementations/seven_zip/lzma/encoder"
        autoload :Decoder, "omnizip/implementations/seven_zip/lzma/decoder"
        autoload :RangeEncoder,
                 "omnizip/implementations/seven_zip/lzma/range_encoder"
        autoload :RangeDecoder,
                 "omnizip/implementations/seven_zip/lzma/range_decoder"
      end

      module LZMA2
        autoload :Encoder, "omnizip/implementations/seven_zip/lzma2/encoder"
      end
    end

    module XZUtils
      module LZMA2
        autoload :Encoder, "omnizip/implementations/xz_utils/lzma2/encoder"
      end
    end
  end
end

# Load convenience module to extend Omnizip with utility methods
require "omnizip/convenience"

# Auto-register formats after all autoloads are set up
Omnizip::Formats::SevenZip.register!
Omnizip::Formats::Rar.register!
Omnizip::Formats::Iso.register!

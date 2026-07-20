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
  autoload :VERSION, "omnizip/version"

  autoload :Error, "omnizip/error"
  autoload :CompressionError, "omnizip/error"
  autoload :DecompressionError, "omnizip/error"
  autoload :AlgorithmNotFoundError, "omnizip/error"
  autoload :UnknownAlgorithmError, "omnizip/error"
  autoload :UnknownChecksumError, "omnizip/error"
  autoload :UnknownFilterError, "omnizip/error"
  autoload :UnknownEncryptionStrategyError, "omnizip/error"
  autoload :ConversionNotSupportedError, "omnizip/error"
  autoload :UnsupportedFormatError, "omnizip/error"
  autoload :FormatError, "omnizip/error"
  autoload :InvalidArchiveError, "omnizip/error"
  autoload :IOOperationError, "omnizip/error"
  autoload :IOError, "omnizip/error"
  autoload :ChecksumError, "omnizip/error"
  autoload :OptimizationNotFoundError, "omnizip/error"
  autoload :ProgressError, "omnizip/error"
  autoload :ETAError, "omnizip/error"
  autoload :NotLicensedError, "omnizip/error"
  autoload :RarNotAvailableError, "omnizip/error"

  autoload :Registry, "omnizip/registry"
  autoload :Algorithm, "omnizip/algorithm"
  autoload :AlgorithmRegistry, "omnizip/algorithm_registry"
  autoload :FormatRegistry, "omnizip/format_registry"
  autoload :OptimizationRegistry, "omnizip/optimization_registry"
  autoload :ChecksumRegistry, "omnizip/checksum_registry"
  autoload :FilterRegistry, "omnizip/filter_registry"

  autoload :Filter, "omnizip/filter"
  autoload :FilterPipeline, "omnizip/filter_pipeline"

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
  autoload :CliOutputFormatter, "omnizip/cli/output_formatter"

  # Implementation namespaces. Each namespace file declares autoloads
  # for its concrete classes. The classes self-register with their
  # registry on load (see lib/omnizip/algorithms/lzma.rb etc.).
  autoload :Algorithms, "omnizip/algorithms"
  autoload :Filters, "omnizip/filters"
  autoload :Checksums, "omnizip/checksums"
  autoload :IO, "omnizip/io"
  autoload :Crypto, "omnizip/crypto"
  autoload :Formats, "omnizip/formats"
  autoload :Zip, "omnizip/zip"
  autoload :Extraction, "omnizip/extraction"
  autoload :Implementations, "omnizip/implementations"
  autoload :ArchiveHandler, "omnizip/archive_handler"
  autoload :ArchiveHandlers, "omnizip/archive_handlers"
  autoload :Convenience, "omnizip/convenience"
end

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

module Omnizip
  module Platform
    autoload :NtfsStreams, "omnizip/platform/ntfs_streams"
  end

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

# Trigger autoload of Convenience so its methods are available on the
# Omnizip module (it calls `extend Convenience` at the bottom of the
# file). Without this, Omnizip.compress_file and friends would not be
# defined until the first manual reference.
Omnizip::Convenience

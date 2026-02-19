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

require_relative "omnizip/version"
require_relative "omnizip/error"
require_relative "omnizip/models/algorithm_metadata"
require_relative "omnizip/models/compression_options"
require_relative "omnizip/models/performance_result"
require_relative "omnizip/models/profile_report"
require_relative "omnizip/models/optimization_suggestion"
require_relative "omnizip/models/progress_options"
require_relative "omnizip/models/eta_result"
require_relative "omnizip/models/filter_config"
require_relative "omnizip/models/filter_chain"
require_relative "omnizip/algorithm"
require_relative "omnizip/algorithm_registry"
require_relative "omnizip/format_registry"
require_relative "omnizip/optimization_registry"

# Algorithms
require_relative "omnizip/algorithms/ppmd_base"
require_relative "omnizip/algorithms/lzma"
require_relative "omnizip/algorithms/lzma2"
require_relative "omnizip/algorithms/ppmd7"
require_relative "omnizip/algorithms/ppmd8"
require_relative "omnizip/algorithms/bzip2"
require_relative "omnizip/algorithms/deflate"
require_relative "omnizip/algorithms/deflate64"
require_relative "omnizip/algorithms/zstandard"

# Filter components
require_relative "omnizip/filter"
require_relative "omnizip/filter_registry"
require_relative "omnizip/filter_pipeline"
require_relative "omnizip/filters/filter_base"
require_relative "omnizip/filters/bcj"
require_relative "omnizip/filters/bcj_x86"
require_relative "omnizip/filters/bcj2"
require_relative "omnizip/filters/bcj_arm"
require_relative "omnizip/filters/bcj_arm64"
require_relative "omnizip/filters/bcj_ppc"
require_relative "omnizip/filters/bcj_sparc"
require_relative "omnizip/filters/bcj_ia64"
require_relative "omnizip/filters/delta"

# Register filters with format-aware registration
require_relative "omnizip/filters/registry"

# Checksum implementations
require_relative "omnizip/checksum_registry"
require_relative "omnizip/checksums/crc_base"
require_relative "omnizip/checksums/crc32"
require_relative "omnizip/checksums/crc64"

# I/O utilities
require_relative "omnizip/io/buffered_input"
require_relative "omnizip/io/buffered_output"
require_relative "omnizip/io/stream_manager"

# Register checksum algorithms
Omnizip::ChecksumRegistry.register(:crc32, Omnizip::Checksums::Crc32)
Omnizip::ChecksumRegistry.register(:crc64, Omnizip::Checksums::Crc64)

# Crypto implementations
require_relative "omnizip/crypto/aes256"

# Archive format support
require_relative "omnizip/formats/seven_zip"
require_relative "omnizip/formats/zip"
require_relative "omnizip/formats/rar"

# Container formats (Weeks 7-10)
require_relative "omnizip/formats/tar"
require_relative "omnizip/formats/gzip"
require_relative "omnizip/formats/bzip2_file"
require_relative "omnizip/formats/xz"
require_relative "omnizip/formats/lzma_alone"
require_relative "omnizip/formats/lzip"

# ISO 9660 CD-ROM format (Weeks 11-14)
require_relative "omnizip/formats/iso"

# Platform-specific features (Weeks 11-14)
require_relative "omnizip/platform"
require_relative "omnizip/platform/ntfs_streams"

# Rubyzip-compatible API
require_relative "omnizip/zip/entry"
require_relative "omnizip/zip/file"
require_relative "omnizip/zip/output_stream"
require_relative "omnizip/zip/input_stream"

# Streaming and in-memory operations (v1.2)
require_relative "omnizip/buffer"
require_relative "omnizip/pipe"
require_relative "omnizip/chunked"
require_relative "omnizip/temp"

# File type detection (v1.3)
require_relative "omnizip/file_type"

# Compression profiles (v1.3)
require_relative "omnizip/profile"

# Progress tracking and ETA calculation (v1.3)
require_relative "omnizip/eta"
require_relative "omnizip/progress"

# Metadata editing (v1.3 Phase 2 Week 6)
require_relative "omnizip/metadata"

# Password support (v1.3 Phase 2 Week 7)
require_relative "omnizip/password"

# Format conversion (v1.3 Phase 2 Week 8)
require_relative "omnizip/converter"

# Link handler for symbolic and hard links (v2.0 Phase 1 Weeks 2-3)
require_relative "omnizip/link_handler"

# Parallel processing (v2.0 Phase 4 Weeks 11-12)
# NOTE: Not auto-loaded to avoid loading fractor unnecessarily.
# Users who need parallel processing should explicitly require it:
#   require "omnizip/parallel"
require_relative "omnizip/models/parallel_options"
# require_relative "omnizip/parallel"  # Lazy-load only when needed

# Performance profiling components
require_relative "omnizip/profiler"
require_relative "omnizip/profiler/method_profiler"
require_relative "omnizip/profiler/memory_profiler"
require_relative "omnizip/profiler/report_generator"

# PAR2 parity archive support
require_relative "omnizip/parity"

# CLI components (cli.rb will require output_formatter itself)
require_relative "omnizip/cli"

# Convenience methods for native API
require_relative "omnizip/convenience"

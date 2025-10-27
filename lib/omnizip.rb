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
require_relative "omnizip/algorithms/zstandard"

# Filter components
require_relative "omnizip/filter_registry"
require_relative "omnizip/filter_pipeline"
require_relative "omnizip/filters/filter_base"
require_relative "omnizip/filters/bcj_x86"
require_relative "omnizip/filters/bcj2"
require_relative "omnizip/filters/bcj_arm"
require_relative "omnizip/filters/bcj_arm64"
require_relative "omnizip/filters/bcj_ppc"
require_relative "omnizip/filters/bcj_sparc"
require_relative "omnizip/filters/bcj_ia64"
require_relative "omnizip/filters/delta"

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

# Register filters
Omnizip::FilterRegistry.register(:"bcj-x86", Omnizip::Filters::BcjX86)
Omnizip::FilterRegistry.register(:bcj2, Omnizip::Filters::Bcj2)
Omnizip::FilterRegistry.register(:"bcj-arm", Omnizip::Filters::BcjArm)
Omnizip::FilterRegistry.register(:"bcj-arm64", Omnizip::Filters::BcjArm64)
Omnizip::FilterRegistry.register(:"bcj-ppc", Omnizip::Filters::BcjPpc)
Omnizip::FilterRegistry.register(:"bcj-sparc", Omnizip::Filters::BcjSparc)
Omnizip::FilterRegistry.register(:"bcj-ia64", Omnizip::Filters::BcjIa64)
# Delta filter auto-registers itself

# Archive format support
require_relative "omnizip/formats/seven_zip"

# Performance profiling components
require_relative "omnizip/profiler"
require_relative "omnizip/profiler/method_profiler"
require_relative "omnizip/profiler/memory_profiler"
require_relative "omnizip/profiler/report_generator"

# CLI components (cli.rb will require output_formatter itself)
require_relative "omnizip/cli"

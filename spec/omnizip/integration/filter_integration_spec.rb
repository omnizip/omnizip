# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
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

require "spec_helper"

RSpec.describe "Filter Integration" do
  describe "Format-aware filter IDs" do
    it "returns correct XZ filter IDs" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :x86)
      expect(bcj.id_for_format(:xz)).to eq(0x04)
    end

    it "returns correct 7z filter IDs" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :x86)
      expect(bcj.id_for_format(:seven_zip)).to eq(0x03030103)
    end

    it "returns correct XZ filter IDs for ARM" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :arm)
      expect(bcj.id_for_format(:xz)).to eq(0x07)
    end

    it "returns correct 7z filter IDs for ARM" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :arm)
      expect(bcj.id_for_format(:seven_zip)).to eq(0x03030501)
    end

    it "raises error for ARM64 in XZ format" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :arm64)
      expect do
        bcj.id_for_format(:xz)
      end.to raise_error(NotImplementedError, /arm64.*not yet supported in XZ/i)
    end

    it "returns correct 7z filter IDs for ARM64" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :arm64)
      expect(bcj.id_for_format(:seven_zip)).to eq(0x03030601)
    end
  end

  describe "FilterChain with multiple filters" do
    it "encodes and decodes correctly with single BCJ filter" do
      chain = Omnizip::Models::FilterChain.new(format: :xz)
      chain.add_filter(name: :"bcj-x86")

      # Create test data with x86 CALL instruction (0xE8)
      original = "test data with x86 CALL\xE8\x00\x00\x00\x00"
      encoded = chain.encode_all(original, 0)
      decoded = chain.decode_all(encoded, 0)

      # Compare bytes since encoding may differ
      expect(decoded.bytes).to eq(original.bytes)
    end

    it "encodes and decodes correctly with BCJ filter using architecture" do
      chain = Omnizip::Models::FilterChain.new(format: :seven_zip)
      chain.add_filter(name: :bcj, architecture: :x86)

      # Create test data with x86 CALL instruction (0xE8)
      original = "test data with x86 CALL\xE8\x00\x00\x00\x00"
      encoded = chain.encode_all(original, 0)
      decoded = chain.decode_all(encoded, 0)

      # Compare bytes since encoding may differ
      expect(decoded.bytes).to eq(original.bytes)
    end

    it "returns empty data for empty chain" do
      chain = Omnizip::Models::FilterChain.new(format: :xz)

      original = "test data"
      encoded = chain.encode_all(original, 0)
      decoded = chain.decode_all(encoded, 0)

      expect(decoded).to eq(original)
    end

    it "checks if chain is empty" do
      chain = Omnizip::Models::FilterChain.new(format: :xz)
      expect(chain.empty?).to be true
      expect(chain.size).to eq(0)

      chain.add_filter(name: :"bcj-x86")
      expect(chain.empty?).to be false
      expect(chain.size).to eq(1)
    end
  end

  describe "7z CoderChain integration" do
    it "uses registered algorithms for LZMA2" do
      coder_info = Omnizip::Formats::SevenZip::Models::CoderInfo.new(
        method_id: Omnizip::Formats::SevenZip::Constants::MethodId::LZMA2,
      )

      chain = Omnizip::Formats::SevenZip::CoderChain
      algorithm = chain.algorithm_for_method(coder_info.method_id)

      expect(algorithm).to eq(:lzma2)
    end

    it "uses registered algorithms for LZMA" do
      coder_info = Omnizip::Formats::SevenZip::Models::CoderInfo.new(
        method_id: Omnizip::Formats::SevenZip::Constants::MethodId::LZMA,
      )

      chain = Omnizip::Formats::SevenZip::CoderChain
      algorithm = chain.algorithm_for_method(coder_info.method_id)

      expect(algorithm).to eq(:lzma)
    end

    it "returns nil for COPY method" do
      coder_info = Omnizip::Formats::SevenZip::Models::CoderInfo.new(
        method_id: Omnizip::Formats::SevenZip::Constants::MethodId::COPY,
      )

      chain = Omnizip::Formats::SevenZip::CoderChain
      algorithm = chain.algorithm_for_method(coder_info.method_id)

      expect(algorithm).to be_nil
    end

    it "maps filter IDs correctly" do
      chain = Omnizip::Formats::SevenZip::CoderChain

      expect(chain.filter_for_method(Omnizip::Formats::SevenZip::Constants::FilterId::BCJ_X86)).to eq(:bcj_x86)
      expect(chain.filter_for_method(Omnizip::Formats::SevenZip::Constants::FilterId::BCJ_ARM)).to eq(:bcj_arm)
      expect(chain.filter_for_method(Omnizip::Formats::SevenZip::Constants::FilterId::DELTA)).to eq(:delta)
    end

    it "returns nil for unknown filter IDs" do
      chain = Omnizip::Formats::SevenZip::CoderChain

      expect(chain.filter_for_method(0xFFFFFFFF)).to be_nil
    end

    it "raises error for unsupported compression method" do
      chain = Omnizip::Formats::SevenZip::CoderChain

      expect do
        chain.algorithm_for_method(0x99999999)
      end.to raise_error(RuntimeError, /Unsupported compression method/)
    end
  end

  describe "FilterRegistry integration" do
    it "returns format-specific filters support status" do
      expect(Omnizip::FilterRegistry.supports_format?(:"bcj-x86",
                                                      :xz)).to be true
      expect(Omnizip::FilterRegistry.supports_format?(:"bcj-x86",
                                                      :seven_zip)).to be true
    end

    it "returns false for unsupported format combinations" do
      # ARM64 is only in 7z, not in XZ
      expect(Omnizip::FilterRegistry.supports_format?(:"bcj-arm64",
                                                      :xz)).to be false
      expect(Omnizip::FilterRegistry.supports_format?(:"bcj-arm64",
                                                      :seven_zip)).to be true
    end

    it "lists all filters for XZ format" do
      xz_filters = Omnizip::FilterRegistry.filters_for_format(:xz)
      expect(xz_filters).to include(:"bcj-x86")
      expect(xz_filters).to include(:"bcj-arm")
      expect(xz_filters).to include(:"bcj-ppc")
      expect(xz_filters).to include(:"bcj-ia64")
      expect(xz_filters).to include(:"bcj-sparc")
      expect(xz_filters).to include(:delta)
      # ARM64 and BCJ2 are NOT in XZ
      expect(xz_filters).not_to include(:"bcj-arm64")
      expect(xz_filters).not_to include(:bcj2)
    end

    it "lists all filters for 7z format" do
      seven_zip_filters = Omnizip::FilterRegistry.filters_for_format(:seven_zip)
      expect(seven_zip_filters).to include(:"bcj-x86")
      expect(seven_zip_filters).to include(:"bcj-arm")
      expect(seven_zip_filters).to include(:"bcj-arm64")
      expect(seven_zip_filters).to include(:"bcj-ppc")
      expect(seven_zip_filters).to include(:"bcj-ia64")
      expect(seven_zip_filters).to include(:"bcj-sparc")
      expect(seven_zip_filters).to include(:delta)
      expect(seven_zip_filters).to include(:bcj2)
      expect(seven_zip_filters).to include(:bcj)
    end

    it "checks if filters are registered" do
      expect(Omnizip::FilterRegistry.registered?(:"bcj-x86")).to be true
      expect(Omnizip::FilterRegistry.registered?(:delta)).to be true
      expect(Omnizip::FilterRegistry.registered?(:unknown_filter)).to be false
    end

    it "returns list of available filters" do
      available = Omnizip::FilterRegistry.available
      expect(available).to include(:"bcj-x86")
      expect(available).to include(:"bcj-arm")
      expect(available).to include(:delta)
      expect(available).to include(:bcj2)
    end
  end

  describe "FilterConfig integration" do
    it "returns format-aware filter IDs using unified BCJ filter" do
      # Use the unified BCJ filter which supports id_for_format
      config = Omnizip::Models::FilterConfig.new(name: :bcj, architecture: :x86)

      expect(config.id_for_format(:xz)).to eq(0x04)
      expect(config.id_for_format(:seven_zip)).to eq(0x03030103)
    end

    it "identifies BCJ filters correctly" do
      # The bcj? method checks for 'bcj_' prefix
      # Old-style filters like bcj-x86 won't match due to hyphen naming
      bcj_config = Omnizip::Models::FilterConfig.new(name: :bcj_x86)
      delta_config = Omnizip::Models::FilterConfig.new(name: :delta)

      expect(bcj_config.bcj?).to be true
      expect(delta_config.bcj?).to be false
    end

    it "identifies Delta filter correctly" do
      delta_config = Omnizip::Models::FilterConfig.new(name: :delta)
      bcj_config = Omnizip::Models::FilterConfig.new(name: :bcj_x86)

      expect(delta_config.delta?).to be true
      expect(bcj_config.delta?).to be false
    end

    it "converts to hash for backward compatibility" do
      config = Omnizip::Models::FilterConfig.new(
        name: :"bcj-x86",
        architecture: :x86,
        properties: "test_props".b,
      )

      hash = config.to_h
      expect(hash[:name]).to eq(:"bcj-x86")
      expect(hash[:architecture]).to eq(:x86)
      expect(hash[:properties]).to eq("test_props".b)
    end
  end
end

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

require_relative "../../../lib/omnizip/filters/registry"

RSpec.describe Omnizip::Filters::Registry do
  # Store original registry state for restoration after tests
  before(:all) do
    @original_registry = Omnizip::FilterRegistry.instance_variable_get(:@filters).clone
  end

  # Reset registry before each test to ensure clean state
  before(:each) do
    Omnizip::FilterRegistry.reset!
  end

  # Restore original registry state after all tests complete
  after(:all) do
    Omnizip::FilterRegistry.instance_variable_set(:@filters, @original_registry)
  end

  describe ".register_all" do
    it "registers all BCJ filters" do
      described_class.register_all

      expect(Omnizip::FilterRegistry.registered?(:"bcj-x86")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-arm")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-arm64")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-ia64")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-ppc")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-sparc")).to be true
      expect(Omnizip::FilterRegistry.registered?(:bcj)).to be true # Unified BCJ
    end

    it "registers Delta filter" do
      described_class.register_all

      expect(Omnizip::FilterRegistry.registered?(:delta)).to be true
    end

    it "registers BCJ2 filter" do
      described_class.register_all

      expect(Omnizip::FilterRegistry.registered?(:bcj2)).to be true
    end
  end

  describe ".register_bcj_filters" do
    it "registers architecture-specific BCJ filters" do
      described_class.register_bcj_filters

      expect(Omnizip::FilterRegistry.registered?(:"bcj-x86")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-arm")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-arm64")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-ia64")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-ppc")).to be true
      expect(Omnizip::FilterRegistry.registered?(:"bcj-sparc")).to be true
    end

    it "registers unified BCJ filter" do
      described_class.register_bcj_filters

      expect(Omnizip::FilterRegistry.registered?(:bcj)).to be true
    end
  end

  describe ".register_delta_filter" do
    it "registers Delta filter" do
      described_class.register_delta_filter

      expect(Omnizip::FilterRegistry.registered?(:delta)).to be true
    end
  end

  describe ".register_bcj2_filter" do
    it "registers BCJ2 filter" do
      described_class.register_bcj2_filter

      expect(Omnizip::FilterRegistry.registered?(:bcj2)).to be true
    end
  end

  describe "format support" do
    before(:each) do
      described_class.register_all
    end

    context "BCJ-x86" do
      it "supports both XZ and 7z formats" do
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-x86",
                                                        :xz)).to be true
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-x86",
                                                        :seven_zip)).to be true
      end
    end

    context "BCJ-ARM" do
      it "supports both XZ and 7z formats" do
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-arm",
                                                        :xz)).to be true
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-arm",
                                                        :seven_zip)).to be true
      end
    end

    context "BCJ-ARM64" do
      it "supports only 7z format (not XZ)" do
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-arm64",
                                                        :xz)).to be false
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-arm64",
                                                        :seven_zip)).to be true
      end
    end

    context "BCJ-IA64" do
      it "supports both XZ and 7z formats" do
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-ia64",
                                                        :xz)).to be true
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-ia64",
                                                        :seven_zip)).to be true
      end
    end

    context "BCJ-PPC" do
      it "supports both XZ and 7z formats" do
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-ppc",
                                                        :xz)).to be true
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-ppc",
                                                        :seven_zip)).to be true
      end
    end

    context "BCJ-SPARC" do
      it "supports both XZ and 7z formats" do
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-sparc",
                                                        :xz)).to be true
        expect(Omnizip::FilterRegistry.supports_format?(:"bcj-sparc",
                                                        :seven_zip)).to be true
      end
    end

    context "Unified BCJ" do
      it "supports 7z format" do
        expect(Omnizip::FilterRegistry.supports_format?(:bcj,
                                                        :seven_zip)).to be true
      end
    end

    context "Delta" do
      it "supports both XZ and 7z formats" do
        expect(Omnizip::FilterRegistry.supports_format?(:delta, :xz)).to be true
        expect(Omnizip::FilterRegistry.supports_format?(:delta,
                                                        :seven_zip)).to be true
      end
    end

    context "BCJ2" do
      it "supports only 7z format (not XZ)" do
        expect(Omnizip::FilterRegistry.supports_format?(:bcj2, :xz)).to be false
        expect(Omnizip::FilterRegistry.supports_format?(:bcj2,
                                                        :seven_zip)).to be true
      end
    end
  end

  describe "filters_for_format" do
    before(:each) do
      described_class.register_all
    end

    it "returns all XZ-supported filters" do
      xz_filters = Omnizip::FilterRegistry.filters_for_format(:xz)

      # XZ supports: x86, ARM, PPC, IA64, SPARC, Delta (NOT ARM64 or BCJ2)
      expect(xz_filters).to include(:"bcj-x86", :"bcj-arm", :"bcj-ia64",
                                    :"bcj-ppc", :"bcj-sparc", :delta)
      expect(xz_filters).not_to include(:"bcj-arm64", :bcj2)
    end

    it "returns all 7z-supported filters" do
      seven_zip_filters = Omnizip::FilterRegistry.filters_for_format(:seven_zip)

      # 7z supports all BCJ filters + Delta + BCJ2
      expect(seven_zip_filters).to include(
        :"bcj-x86",
        :"bcj-arm",
        :"bcj-arm64",
        :"bcj-ia64",
        :"bcj-ppc",
        :"bcj-sparc",
        :bcj,
        :delta,
        :bcj2,
      )
    end
  end

  describe "get_for_format" do
    before(:each) do
      described_class.register_all
    end

    it "returns filter instance for supported format" do
      filter = Omnizip::FilterRegistry.get_for_format(:"bcj-x86", :xz)
      expect(filter).to be_a(Omnizip::Filters::BcjX86)
    end

    it "raises error for unsupported format" do
      expect do
        Omnizip::FilterRegistry.get_for_format(:"bcj-arm64", :xz)
      end.to raise_error(ArgumentError, /not supported for format/)
    end
  end

  describe "total filter count" do
    it "registers expected number of filters" do
      described_class.register_all

      # 6 individual BCJ + 1 unified BCJ + Delta + BCJ2 = 9 filters
      expect(Omnizip::FilterRegistry.available.length).to eq(9)
    end
  end
end

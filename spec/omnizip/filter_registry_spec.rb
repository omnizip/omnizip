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

require "spec_helper"
require "omnizip/filters/filter_base"

RSpec.describe Omnizip::FilterRegistry do
  # Test filter class for format-aware registration
  class TestFilter < Omnizip::Filters::FilterBase
    def encode(data, _position = 0)
      data
    end

    def decode(data, _position = 0)
      data
    end

    def self.metadata
      { name: "Test", description: "Test filter" }
    end
  end

  # Another test filter class
  class AnotherTestFilter < Omnizip::Filters::FilterBase
    def encode(data, _position = 0)
      data
    end

    def decode(data, _position = 0)
      data
    end

    def self.metadata
      { name: "Another Test", description: "Another test filter" }
    end
  end

  before(:each) do
    # Reset registry before each test
    described_class.reset!
  end

  describe ".register_with_formats" do
    it "registers filter with format support" do
      described_class.register_with_formats(:test_bcj, TestFilter,
                                            formats: [:xz])
      expect(described_class.supports_format?(:test_bcj, :xz)).to be true
      expect(described_class.supports_format?(:test_bcj,
                                              :seven_zip)).to be false
    end

    it "registers filter with default formats" do
      described_class.register_with_formats(:test_bcj, TestFilter)
      expect(described_class.supports_format?(:test_bcj, :xz)).to be true
      expect(described_class.supports_format?(:test_bcj, :seven_zip)).to be true
    end

    it "raises when name is nil" do
      expect do
        described_class.register_with_formats(nil, TestFilter)
      end.to raise_error(ArgumentError, /Filter name cannot be nil/)
    end

    it "raises when class is nil" do
      expect do
        described_class.register_with_formats(:test, nil)
      end.to raise_error(ArgumentError, /Filter class cannot be nil/)
    end

    it "allows multiple format registrations" do
      described_class.register_with_formats(:test1, TestFilter,
                                            formats: [:xz])
      described_class.register_with_formats(:test2, AnotherTestFilter,
                                            formats: [:seven_zip])

      expect(described_class.registered?(:test1)).to be true
      expect(described_class.registered?(:test2)).to be true
    end
  end

  describe ".get_for_format" do
    it "returns filter instance for format" do
      described_class.register_with_formats(:test_bcj, TestFilter,
                                            formats: [:xz])
      filter = described_class.get_for_format(:test_bcj, :xz)
      expect(filter).to be_a(TestFilter)
    end

    it "returns new instance each time" do
      described_class.register_with_formats(:test_bcj, TestFilter,
                                            formats: [:xz])
      filter1 = described_class.get_for_format(:test_bcj, :xz)
      filter2 = described_class.get_for_format(:test_bcj, :xz)
      expect(filter1).not_to eq(filter2)
    end

    it "raises KeyError when filter not found" do
      expect do
        described_class.get_for_format(:nonexistent, :xz)
      end.to raise_error(KeyError, /Filter not found/)
    end

    it "raises ArgumentError when format not supported" do
      described_class.register_with_formats(:test_bcj, TestFilter,
                                            formats: [:xz])
      expect do
        described_class.get_for_format(:test_bcj, :seven_zip)
      end.to raise_error(ArgumentError, /not supported for format/)
    end
  end

  describe ".supports_format?" do
    it "returns true for supported format" do
      described_class.register_with_formats(:test_bcj, TestFilter,
                                            formats: [:xz])
      expect(described_class.supports_format?(:test_bcj, :xz)).to be true
    end

    it "returns false for unsupported format" do
      described_class.register_with_formats(:test_bcj, TestFilter,
                                            formats: [:xz])
      expect(described_class.supports_format?(:test_bcj,
                                              :seven_zip)).to be false
    end

    it "returns false for unregistered filter" do
      expect(described_class.supports_format?(:nonexistent, :xz)).to be false
    end

    it "handles old-style registration (backward compatibility)" do
      described_class.register(:old_style, TestFilter)
      expect(described_class.supports_format?(:old_style, :xz)).to be true
    end
  end

  describe ".filters_for_format" do
    before(:each) do
      described_class.register_with_formats(:xz_only, TestFilter,
                                            formats: [:xz])
      described_class.register_with_formats(:seven_zip_only, AnotherTestFilter,
                                            formats: [:seven_zip])
      described_class.register_with_formats(:both, TestFilter,
                                            formats: %i[xz seven_zip])
    end

    it "returns filters for XZ format" do
      xz_filters = described_class.filters_for_format(:xz)
      expect(xz_filters).to include(:xz_only, :both)
      expect(xz_filters).not_to include(:seven_zip_only)
    end

    it "returns filters for 7z format" do
      sz_filters = described_class.filters_for_format(:seven_zip)
      expect(sz_filters).to include(:seven_zip_only, :both)
      expect(sz_filters).not_to include(:xz_only)
    end

    it "returns empty array when no filters support format" do
      described_class.reset!
      expect(described_class.filters_for_format(:xz)).to eq([])
    end

    it "handles old-style registration (backward compatibility)" do
      described_class.register(:old_style, TestFilter)
      all_formats = described_class.filters_for_format(:xz)
      expect(all_formats).to include(:old_style)
    end
  end

  describe "backward compatibility with original API" do
    it ".register still works" do
      described_class.register(:test, TestFilter)
      expect(described_class.registered?(:test)).to be true
    end

    it ".get returns the class for old-style registration" do
      described_class.register(:test, TestFilter)
      expect(described_class.get(:test)).to eq(TestFilter)
    end

    it ".get raises UnknownFilterError for unregistered filter" do
      expect do
        described_class.get(:nonexistent)
      end.to raise_error(Omnizip::UnknownFilterError, /Unknown filter/)
    end

    it ".available includes both old and new registrations" do
      described_class.register(:old_style, TestFilter)
      described_class.register_with_formats(:new_style, AnotherTestFilter,
                                            formats: [:xz])

      expect(described_class.available).to include(:old_style, :new_style)
    end
  end

  describe ".reset!" do
    it "clears all registrations" do
      described_class.register(:test, TestFilter)
      described_class.register_with_formats(:test2, AnotherTestFilter,
                                            formats: [:xz])

      described_class.reset!
      expect(described_class.available).to eq([])
      expect(described_class.registered?(:test)).to be false
    end
  end

  after(:all) do
    # Restore the registry state for other tests
    Omnizip::Filters::Registry.register_all
  end
end

# frozen_string_literal: true

require "spec_helper"

# Regression spec for the v0.3.10 fontist breakage (metanorma-docker
# issue #241): each format file is loaded in isolation. The file body
# must not reference any constant that is only resolvable after the
# entry-point autoload chain has been set up.
#
# Note: this spec does NOT assert that the autoload chain survives an
# external gem doing `require "omnizip/formats/cpio"` BEFORE
# `require "omnizip"`. That pattern reaches across the public/private
# boundary into internal files and is unsupported. The contract is
# documented in the README: external code must `require "omnizip"` to
# use the gem.
RSpec.describe "format file direct require" do
  FORMATS = %w[
    cpio gzip lzip lzma_alone rar bzip2_file msi xar iso zip seven_zip ole tar
  ].freeze

  FORMATS.each do |fmt|
    it "'require \"omnizip/formats/#{fmt}\"' loads without raising" do
      expect do
        load_without_side_effects("omnizip/formats/#{fmt}")
      end.not_to raise_error
    end
  end

  it "every format is discoverable via FormatRegistry after omnizip loaded" do
    require "omnizip"

    expected = %w[.cpio .gz .gzip .lz .lzip .lzma .rar .bz2 .bzip2 .msi .msp
                  .xar .iso .zip .7z .ole .tar]
    expected.each do |ext|
      expect(Omnizip::FormatRegistry.get(ext)).not_to be_nil,
                                                       "no handler for #{ext}"
    end
  end

  def load_without_side_effects(path)
    captured = $LOADED_FEATURES.dup
    begin
      Kernel.require(path)
    ensure
      ($LOADED_FEATURES - captured).each do |f|
        next unless f.end_with?("/lib/#{path}.rb")

        $LOADED_FEATURES.delete(f)
      end
    end
  end
end

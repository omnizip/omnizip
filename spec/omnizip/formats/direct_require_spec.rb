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

  it "ArchiveHandler resolves :zip and :tar via lazy triggers" do
    require "omnizip"

    expect(Omnizip::ArchiveHandler.for(:zip)).to be_a(Omnizip::ArchiveHandlers::ZipHandler)
    expect(Omnizip::ArchiveHandler.for(:tar)).to be_a(Omnizip::ArchiveHandlers::TarHandler)
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

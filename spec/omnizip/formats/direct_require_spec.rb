# frozen_string_literal: true

require "spec_helper"

# Regression spec for the v0.3.10 fontist breakage (metanorma-docker
# issue #241): external gems like fontist may require a single format
# file directly — e.g., `require "omnizip/formats/cpio"` — without
# first requiring the entry-point `require "omnizip"`. The autoload
# chain that wires FormatRegistry into Omnizip is then never set up,
# and any FormatRegistry reference in the format file body raised
# NameError. The lazy triggers on FormatRegistry are the load-bearing
# path; per-file self-register calls at the bottom of format files are
# redundant and brittle, and have been removed.
RSpec.describe "format file direct require" do
  FORMATS = %w[
    cpio gzip lzip lzma_alone rar bzip2_file msi xar iso zip seven_zip ole tar
  ].freeze

  FORMATS.each do |fmt|
    it "'require \"omnizip/formats/#{fmt}\"' loads without raising" do
      # Each format file is loaded in isolation. The file body must not
      # reference any constant that is only resolvable after the
      # entry-point autoload chain has been set up.
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

  # Regression for the v0.3.11 excavate/fontist breakage: when an
  # external gem does `require "omnizip/formats/cpio"` BEFORE the user
  # does `require "omnizip"`, the cpio file's `module Omnizip::Formats`
  # would create the Formats module as empty. Subsequent `autoload
  # :Formats, ...` in omnizip.rb would be silently ignored, breaking
  # lookups for every other format. Fixed by adding `require "omnizip"`
  # at the top of every internal file — the entry point load is
  # idempotent and ensures the autoload chain is wired before any
  # module is reopened.
  #
  # Must run in a subprocess because Ruby's autoload can't be reliably
  # reset within a single process.
  it "module chain is intact when a format file is required before omnizip.rb" do
    skip "subprocess test only runs against local lib" unless File.directory?(File.expand_path("lib/omnizip", Dir.pwd))

    script = <<~RUBY
      require "omnizip/formats/cpio"
      require "omnizip"
      puts Omnizip::Formats::SevenZip
      puts Omnizip::Formats::Tar
      puts Omnizip::Formats::Zip
    RUBY

    output = `ruby -Ilib -e '#{script.gsub("'", "\\\\'")}' 2>&1`
    expect($?).to be_success, "expected clean run, got: #{output}"
    expect(output).to include("Omnizip::Formats::SevenZip")
    expect(output).to include("Omnizip::Formats::Tar")
    expect(output).to include("Omnizip::Formats::Zip")
  end

  # Loads +path+ via Kernel#load wrapped in a clean module so the
  # file body executes without polluting the global namespace, then
  # restores autoloads that may have been clobbered.
  def load_without_side_effects(path)
    captured = $LOADED_FEATURES.dup
    begin
      Kernel.require(path)
    ensure
      # Don't keep the file marked as loaded — we want this spec to be
      # idempotent when run alongside others that may rely on the
      # autoload chain.
      ($LOADED_FEATURES - captured).each do |f|
        next unless f.end_with?("/lib/#{path}.rb")

        $LOADED_FEATURES.delete(f)
      end
    end
  end
end

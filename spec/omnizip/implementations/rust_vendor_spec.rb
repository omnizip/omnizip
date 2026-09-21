# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "spec_helper"
require "omnizip/implementations/rust"

# Prebuilt-binary distribution: the platform gem vendors its cdylib
# at vendor/ (lib/omnizip/vendor in the built gem tree — here at the
# gem root, matching `rake rust:build`'s output location). Resolution
# must prefer it over dev checkouts, honor the explicit ENV override,
# and honor the OMNIZIP_NO_RUST=1 kill switch so environments without
# Rust (or without the binary, e.g. JRuby) stay on the pure-Ruby core.
RSpec.describe "Omnizip::Implementations::Rust::Library cdylib resolution" do
  let(:library) { Omnizip::Implementations::Rust::Library }
  let(:dylib) { library.resolve_path&.to_s }

  around do |ex|
    old_no_rust = ENV.fetch("OMNIZIP_NO_RUST", nil)
    old_explicit = ENV.fetch("OMNIZIP_FFI_DYLIB", nil)
    ENV.delete("OMNIZIP_NO_RUST")
    ENV.delete("OMNIZIP_FFI_DYLIB")
    library.forget!
    ex.run
    if old_no_rust
      ENV["OMNIZIP_NO_RUST"] = old_no_rust
    else
      ENV.delete("OMNIZIP_NO_RUST")
    end
    if old_explicit
      ENV["OMNIZIP_FFI_DYLIB"] = old_explicit
    else
      ENV.delete("OMNIZIP_FFI_DYLIB")
    end
    library.forget!
  end

  describe ".resolve_path" do
    it "prefers the vendor dir over a later candidate" do
      skip "no cdylib available in this environment to stage" unless dylib

      Dir.mktmpdir do |tmp|
        vendor = Pathname.new(tmp).join("vendor")
        other = Pathname.new(tmp).join("other")
        [vendor, other].each(&:mkpath)
        FileUtils.cp(dylib, vendor.join("libomnizip_ffi.dylib"))
        FileUtils.cp(dylib, other.join("libomnizip_ffi.so"))

        got = library.resolve_path([other, vendor])
        expect(got.to_s).to end_with("vendor/libomnizip_ffi.dylib")
      end
    end

    it "returns nil when no candidate holds a cdylib" do
      Dir.mktmpdir do |tmp|
        empty = Pathname.new(tmp).join("empty")
        empty.mkpath
        expect(library.resolve_path([empty])).to be_nil
      end
    end

    it "returns nil under OMNIZIP_NO_RUST=1 even with a candidate present" do
      skip "no cdylib available in this environment to stage" unless dylib

      Dir.mktmpdir do |tmp|
        vendor = Pathname.new(tmp).join("vendor")
        vendor.mkpath
        FileUtils.cp(dylib, vendor.join("libomnizip_ffi.dylib"))
        ENV["OMNIZIP_NO_RUST"] = "1"

        expect(library.resolve_path([vendor])).to be_nil
        expect(library.instance).to be_nil
      end
    end

    it "the OMNIZIP_FFI_DYLIB override beats the vendor dir" do
      skip "no cdylib available in this environment to stage" unless dylib

      Dir.mktmpdir do |tmp|
        vendor = Pathname.new(tmp).join("vendor")
        explicit_dir = Pathname.new(tmp).join("explicit")
        [vendor, explicit_dir].each(&:mkpath)
        FileUtils.cp(dylib, vendor.join("libomnizip_ffi.dylib"))
        FileUtils.cp(dylib, explicit_dir.join("override.dylib"))
        ENV["OMNIZIP_FFI_DYLIB"] = explicit_dir.join("override.dylib").to_s

        expect(library.resolve_path.to_s).to eq(ENV.fetch("OMNIZIP_FFI_DYLIB", nil))
      end
    end
  end

  describe ".dylib_version" do
    it "reports a semver or nil for pre-symbol dylibs" do
      skip "no cdylib available in this environment" unless dylib

      version = library.dylib_version
      expect(version).to(satisfy { |v| v.nil? || v.match?(/\A\d+\.\d+\.\d+\z/) })
    end
  end

  it "the pure-Ruby core still round-trips with the tier disabled" do
    ENV["OMNIZIP_NO_RUST"] = "1"

    data = "pure ruby fallback " * 1000
    compressed = Omnizip::Algorithms::Deflate.compress(data)
    expect(Omnizip::Algorithms::Deflate.decompress(compressed)).to eq(data)
  end
end

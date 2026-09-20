# frozen_string_literal: true

require "spec_helper"

# Ruby 4.0 moved fiddle out of the default gems — require lazily
# and skip the differential when it is unavailable.
begin
  require "fiddle"
rescue LoadError
  # :nocov:
end

# Cross-tier differential: pure-Ruby cores vs the omnizip-ffi Rust
# cdylib (TODO.ref-parity/62). Owner guidance 2026-09-19: some Ruby
# cores carry bugs the Rust ports fixed — this spec is the
# instrument that SURFACES them, treating decode disagreement as a
# Ruby-side accuracy finding (the Rust decoders carry the fixes).
#
# Skipped (not failed) when the cdylib is not loadable: the
# pure-Ruby-only environment must stay green.
RSpec.describe "cross-tier differential" do
  let(:library) do
    path = ENV["OMNIZIP_FFI_DYLIB"] ||
      File.expand_path("../../../omnizip-rs/target/release/libomnizip_ffi.dylib", __dir__)
    return nil unless File.file?(path)

    handle = Fiddle.dlopen(path)
    compress = Fiddle::Function.new(handle["ozip_compress"],
                                    [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T,
                                     Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    decompress = Fiddle::Function.new(handle["ozip_decompress"],
                                      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T,
                                       Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    free = Fiddle::Function.new(handle["ozip_free"],
                                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T], Fiddle::TYPE_VOID)
    { compress: compress, decompress: decompress, free: free }
  end

  def rust_decompress(codec, data)
    out_len = [0].pack("Q")
    # usize::MAX = unknown length (the streaming-caller contract).
    ptr = library[:decompress].call(codec, data, data.bytesize, 0xFFFF_FFFF_FFFF_FFFF, out_len)
    raise "ffi decompress failed" if ptr.null?

    len = out_len.unpack1("Q")
    string = ptr.to_s(len)
    library[:free].call(ptr, len)
    string
  end

  def rust_compress(codec, data, level)
    out_len = [0].pack("Q")
    ptr = library[:compress].call(codec, data, data.bytesize, level, out_len)
    raise "ffi compress failed" if ptr.null?

    len = out_len.unpack1("Q")
    string = ptr.to_s(len)
    library[:free].call(ptr, len)
    string
  end

  let(:corpus) do
    text = "the quick brown fox jumps over the lazy dog. " * 200
    binary = (0...4096).map { |i| (i * 31 % 256).chr }.join
    periodic = ("ab" * 5000)
    empty = ""
    { "text" => text, "binary" => binary, "periodic" => periodic, "empty" => empty }
  end

  describe "bzip2 decode agreement" do
    it "decodes the Rust encoder's output identically on both tiers" do
      skip "omnizip-ffi cdylib not built" if library.nil?

      corpus.each do |label, plaintext|
        compressed = rust_compress("bzip2", plaintext, 6)
        ruby_decoded = Omnizip::Algorithms::BZip2::Bz2.decompress(compressed)
        rust_decoded = rust_decompress("bzip2", compressed)
        expect(ruby_decoded).to eq(plaintext), "ruby decode diverged on #{label}"
        expect(rust_decoded).to eq(plaintext), "rust decode diverged on #{label}"
      end
    end

    it "decodes the Ruby encoder's output identically on both tiers" do
      skip "omnizip-ffi cdylib not built" if library.nil?

      corpus.each do |label, plaintext|
        compressed = Omnizip::Algorithms::BZip2::Bz2.compress(plaintext, 6)
        ruby_decoded = Omnizip::Algorithms::BZip2::Bz2.decompress(compressed)
        rust_decoded = rust_decompress("bzip2", compressed)
        expect(ruby_decoded).to eq(plaintext), "ruby decode diverged on #{label}"
        expect(rust_decoded).to eq(plaintext), "rust decode diverged on #{label}"
      end
    end
  end

  describe "backends tier policy" do
    # One sequential example: the tier switch reads process-global
    # state (cached handle + ENV), so split examples race under
    # random ordering.
    it "resolves auto/ruby/absence deterministically" do
      backend = ENV.fetch("OMNIZIP_BACKEND", nil)
      dylib = ENV.fetch("OMNIZIP_FFI_DYLIB", nil)
      begin
        Omnizip::Implementations::Rust::Library.forget!
        ENV["OMNIZIP_FFI_DYLIB"] = "/nonexistent/libomnizip_ffi.dylib"
        # A stale explicit path must not shadow a REAL source: the
        # sibling-checkout discovery takes over when one exists
        # (local dev); on a standalone checkout nothing resolves and
        # the tier falls back to Ruby. Both are correct.
        # Same computation the loader uses (four ups reach the
        # source root that holds the omnizip-rs sibling).
        # Standalone checkout (CI): nothing resolves, tier = Ruby.
        # With a sibling checkout the later `auto` block proves the
        # load positively, so this branch only asserts absence.
        sibling = File.expand_path("../../../../omnizip-rs/target/release", __dir__)
        unless File.directory?(sibling)
          expect(Omnizip::Implementations::Rust::Library.instance).to be_nil
          expect(Omnizip::Backends.for("bzip2", :decode)).to eq(Omnizip::Backends::RubyBackend)
        end

        ENV["OMNIZIP_BACKEND"] = "ruby"
        expect(Omnizip::Backends.for("bzip2", :decode)).to eq(Omnizip::Backends::RubyBackend)

        ENV["OMNIZIP_FFI_DYLIB"] = dylib if library
        if library
          Omnizip::Implementations::Rust::Library.forget!
          ENV["OMNIZIP_BACKEND"] = "auto"
          # Rust is the authority (2026-09-20 policy): BOTH directions
          # route through Rust when the library loads.
          expect(Omnizip::Backends.for("bzip2", :decode)).to eq(Omnizip::Backends::RustBackend)
          expect(Omnizip::Backends.for("bzip2", :encode)).to eq(Omnizip::Backends::RustBackend)
        end
      ensure
        ENV["OMNIZIP_BACKEND"] = backend
        ENV["OMNIZIP_FFI_DYLIB"] = dylib
        Omnizip::Implementations::Rust::Library.forget!
      end
    end
  end

  describe "algorithm-level dual path" do
    it "round-trips bzip2 through the tiered algorithm API" do
      skip "omnizip-ffi cdylib not built" if library.nil?

      require "stringio"
      corpus.each do |label, plaintext|
        out = StringIO.new(+"".b)
        Omnizip::Algorithms::BZip2.new.compress(StringIO.new(plaintext), out)
        restored = StringIO.new(+"".b)
        Omnizip::Algorithms::BZip2.new.decompress(StringIO.new(out.string), restored)
        expect(restored.string).to eq(plaintext), "round-trip diverged on #{label}"
      end
    end
  end
end

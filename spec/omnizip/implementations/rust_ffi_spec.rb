# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "spec_helper"
require "omnizip/implementations/rust"

# The ffi binding (leptris-ruby's model): JRuby and TruffleRuby ship
# no Fiddle, so the ffi gem is their ONLY path to the tier. MRI can
# force the same path with OMNIZIP_BINDING=ffi, which is how these
# specs prove the ffi layer works — the exact code those engines run.
RSpec.describe "Omnizip::Implementations::Rust::FfiLibrary" do
  let(:library) { Omnizip::Implementations::Rust::Library }

  around do |ex|
    old = ENV.fetch("OMNIZIP_BINDING", nil)
    ENV["OMNIZIP_BINDING"] = "ffi"
    library.forget!
    ex.run
    if old
      ENV["OMNIZIP_BINDING"] = old
    else
      ENV.delete("OMNIZIP_BINDING")
    end
    library.forget!
  end

  it "loads the cdylib through the ffi gem and reports the layer" do
    skip "omnizip-ffi cdylib not built" if library.resolve_path.nil?

    require "ffi"
    expect(library.instance).to be_a(Omnizip::Implementations::Rust::FfiLibrary)
    expect(library.binding_layer).to eq("ffi")
    expect(library.dylib_version).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "codec tier round-trips through ffi" do
    skip "omnizip-ffi cdylib not built" if library.resolve_path.nil?

    data = "ffi binding round-trip " * 2000
    enc = library.instance.compress("zlib", data, 6)
    expect(library.instance.decompress("zlib", enc, data.bytesize)).to eq(data)
  end

  it "the archive tier (ArchHandle) lists and reads through ffi" do
    skip "omnizip-ffi cdylib not built" if library.resolve_path.nil?

    data = "ffi archive tier " * 500
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.zip")
      Omnizip::Zip::File.open(path, create: true) do |z|
        z.send(:add_data, "ffi.txt", data)
      end

      Omnizip::Implementations::Rust::Archive.open(File.binread(path)) do |arch|
        expect(arch.entry_names).to eq(["ffi.txt"])
        expect(arch.read_entry(0)).to eq(data)
      end
    end
  end

  it "archive entries ride the ffi path inside the handler tier" do
    skip "omnizip-ffi cdylib not built" if library.resolve_path.nil?

    data = "ffi handler tier " * 1000
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.tar")
      Omnizip::Formats::Tar.create(path) do |w|
        w.add_data("f.txt", data)
      end

      names = Omnizip::Backends.archive_entry_names(path)
      expect(names).to eq(["f.txt"])
      expect(Omnizip::Backends.archive_read_entry(path, "f.txt")).to eq(data)
    end
  end

  it "a rust-side error surfaces as Omnizip::Error with the dylib's message" do
    skip "omnizip-ffi cdylib not built" if library.resolve_path.nil?

    expect do
      library.instance.decompress("zlib", "not a zlib stream", 10)
    end.to raise_error(Omnizip::Implementations::Rust::Error)
  end
end

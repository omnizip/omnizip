# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "spec_helper"
require "omnizip/implementations/rust"

# Archive-level tier across handlers: for every format where the Rust
# reader's entry model MATCHES the Ruby handler's (verified here), list
# (names) and read_entry ride the cdylib first and fall back to Ruby.
# OLE is intentionally NOT wired: the Ruby reader lists top-level
# entries while the Rust reader flattens the storage tree — wiring it
# would change user-visible names, so the OLE handler stays pure-Ruby
# (pinned below). RPM's tier assertions need dylib >= 0.21.112 (the
# './'-prefix normalization release); on older dylibs the rpm names
# diverge and its specs skip.
RSpec.describe "archive tier across handlers" do
  let(:library) { Omnizip::Implementations::Rust::Library }
  let(:dylib_version) { library.dylib_version }

  def dylib_at_least(version)
    return false if dylib_version.nil?

    Gem::Version.new(dylib_version) >= Gem::Version.new(version)
  end

  def build_tar(path)
    Omnizip::Formats::Tar.create(path) do |w|
      w.add_data("a.txt", "tar tier " * 100)
      w.add_data("sub/b.bin", (0..999).map { |i| (i % 251).chr }.join)
    end
  end

  def build_cpio(path)
    src = "#{path}.src"
    FileUtils.mkdir_p(src)
    File.binwrite("#{src}/c.txt", "cpio tier " * 100)
    File.binwrite("#{src}/d.bin", (0..499).map { |i| (i % 241).chr }.join)
    Omnizip::Formats::Cpio.create(path) do |w|
      w.add_file("#{src}/c.txt", "c.txt")
      w.add_file("#{src}/d.bin", "d.bin")
    end
  end

  def build_iso(path)
    src = "#{path}.src"
    FileUtils.mkdir_p(src)
    File.binwrite("#{src}/i.txt", "iso tier " * 100)
    Omnizip::Formats::Iso.create(path) do |w|
      w.add_file("#{src}/i.txt", "I.TXT")
    end
  end

  def build_xar(path)
    Omnizip::Formats::Xar.create(path) do |w|
      w.add_data("x.txt", "xar tier " * 100)
    end
  end

  def fixture(name)
    File.expand_path("../../fixtures/#{name}", __dir__)
  end

  # format => [handler, path-lambda, password]
  def cases(tmp)
    {
      "tar" => [Omnizip::ArchiveHandlers::TarHandler.new, -> {
        p = File.join(tmp, "t.tar")
        build_tar(p)
        p
      }, nil],
      "cpio" => [Omnizip::ArchiveHandlers::CpioHandler.new, -> {
        p = File.join(tmp, "t.cpio")
        build_cpio(p)
        p
      }, nil],
      "iso" => [Omnizip::ArchiveHandlers::IsoHandler.new, -> {
        p = File.join(tmp, "t.iso")
        build_iso(p)
        p
      }, nil],
      "xar" => [Omnizip::ArchiveHandlers::XarHandler.new, -> {
        p = File.join(tmp, "t.xar")
        build_xar(p)
        p
      }, nil],
      "7z" => [Omnizip::ArchiveHandlers::SevenZipHandler.new, -> { fixture("seven_zip/multi_file.7z") }, nil],
      "rar5" => [Omnizip::ArchiveHandlers::RarHandler.new,
                 -> { fixture("rar/libarchive_reference/test_read_format_rar5_stored_manyfiles.rar") }, nil],
      "rar5-encrypted" => [Omnizip::ArchiveHandlers::RarHandler.new,
                           -> { fixture("rar/libarchive_reference/test_read_format_rar5_solid_encrypted.rar") },
                           "password"],
      "rpm" => [Omnizip::ArchiveHandlers::RpmHandler.new,
                -> { fixture("rpm/pagure-mirror-5.13.2-5.fc35.noarch.rpm") }, nil],
    }
  end

  it "tier names and bytes agree with the Ruby handlers on every wired format" do
    skip "omnizip-ffi cdylib not built" if library.instance.nil?

    Dir.mktmpdir do |tmp|
      cases(tmp).each do |name, (handler, make_path, password)|
        if name == "rpm" && !dylib_at_least("0.21.112")
          skip "rpm tier needs dylib >= 0.21.112 ('./'-prefix fix); loaded #{dylib_version.inspect}"
        end

        path = make_path.call
        ruby_names = handler.list(path, password: password)
        tier_names = Omnizip::Backends.archive_entry_names(path, password: password)
        expect(tier_names).not_to be_nil, "#{name}: tier could not open the archive"
        expect(tier_names.sort).to eq(ruby_names.sort), "#{name}: entry names diverge"

        target = ruby_names.first
        ruby_bytes = handler.read_entry(path, target, password: password)
        tier_bytes = Omnizip::Backends.archive_read_entry(path, target, password: password)
        expect(tier_bytes).to eq(ruby_bytes), "#{name}: read_entry bytes diverge"
      end
    end
  end

  it "a wrong rar5 password never yields plaintext bytes" do
    skip "omnizip-ffi cdylib not built" if library.instance.nil?

    path = fixture("rar/libarchive_reference/test_read_format_rar5_solid_encrypted.rar")
    skip "encrypted rar fixture missing" unless File.file?(path)

    handler = Omnizip::ArchiveHandlers::RarHandler.new
    names = handler.list(path)
    first = names.first
    expect(handler.read_entry(path, first, password: "password")).to be_a(String)
    expect do
      handler.read_entry(path, first, password: "definitely-wrong")
    end.to raise_error(StandardError)
  end

  it "the OLE handler stays pure-Ruby (pinned model divergence)" do
    skip "omnizip-ffi cdylib not built" if library.instance.nil?

    path = fixture("ole/oleWithDirs.ole")
    ruby_names = Omnizip::ArchiveHandlers::OleHandler.new.list(path)
    expect(ruby_names).to include("file1")

    tier_names = Omnizip::Backends.archive_entry_names(path)
    return if tier_names.nil? # no dylib: fallback, trivially fine

    # The tier CAN read OLE, but its full-tree naming must never leak
    # through the handler — the divergence is pinned, not fixed.
    expect(tier_names.sort).not_to eq(ruby_names.sort)
  end
end

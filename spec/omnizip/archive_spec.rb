# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"
require "tmpdir"

RSpec.describe Omnizip::Archive do
  let(:source) do
    rng = Random.new(7)
    words = %w[alpha beta gamma delta epsilon zeta]
    Array.new(400) { words.sample(rng.rand(2) + 1).join(" ") }.join("\n")
  end
  let(:srcdir) do
    Dir.mktmpdir("omnizip-arch").tap do |dir|
      stable = File.join(dir, "mydir")
      Dir.mkdir(stable)
      File.binwrite(File.join(stable, "a.txt"), "top-level\n")
      Dir.mkdir(File.join(stable, "sub"))
      File.binwrite(File.join(stable, "sub", "b.txt"), source)
    end
  end
  let(:datadir) { File.join(srcdir, "mydir") }
  let(:outdir) { Dir.mktmpdir("omnizip-arch") }
  let(:input) do
    Tempfile.new("omnizip-arch-in").tap do |f|
      f.binmode
      f.write(source)
      f.flush
    end
  end

  after do
    FileUtils.rm_rf(srcdir)
    FileUtils.rm_rf(outdir)
    ENV.delete("OMNIZIP_PASSWORD")
  end

  def create_archive(path, **options)
    described_class.create(File.join(outdir, path), **options) do |archive|
      archive.add_file(input.path, "documents/input.txt")
      archive.add_directory(datadir)
      archive.add_data("notes/readme.txt", "generated\n")
    end
  end

  {
    "zip via default" => ["doc.zip", {}],
    "7z via format keyword" => ["doc.7z", { format: :seven_zip }],
    "7z via extension" => ["doc.7z", {}],
    "tar via extension" => ["doc.tar", {}],
  }.each do |label, (name, options)|
    it "round-trips #{label}" do
      create_archive(name, **options)

      described_class.open(File.join(outdir, name)) do |archive|
        names = archive.entries.map(&:name)
        expect(names).to include("documents/input.txt", "notes/readme.txt",
                                 "mydir/a.txt", "mydir/sub/b.txt")

        file_entry = archive.entries.find { |e| e.name == "mydir/sub/b.txt" }
        expect(file_entry.directory?).to be false
        expect(file_entry.size).to eq(source.bytesize)

        expect(archive.read("mydir/sub/b.txt")).to eq(source)
        expect(archive.read("notes/readme.txt")).to eq("generated\n")

        archive.extract("mydir/sub/b.txt", File.join(outdir, "restored.txt"))
        expect(File.binread(File.join(outdir, "restored.txt"))).to eq(source)

        archive.extract_all(File.join(outdir, "all"))
        expect(File.binread(File.join(outdir, "all", "mydir/sub", "b.txt")))
          .to eq(source)

        archive.extract_matching("mydir/sub/*.txt", File.join(outdir, "match"))
        expect(File.exist?(File.join(outdir, "match", "mydir", "sub", "b.txt")))
          .to be true
        expect(File.exist?(File.join(outdir, "match", "documents")))
          .to be false
      end
    end
  end

  it "yields metadata entries for explicit directory entries where the format keeps them" do
    create_archive("dirs.zip")
    create_archive("dirs.tar")

    ["dirs.zip", "dirs.tar"].each do |name|
      described_class.open(File.join(outdir, name)) do |archive|
        dir_entry = archive.entries.find { |e| e.name == "mydir/sub/" }
        expect(dir_entry).not_to be_nil
        expect(dir_entry.directory?).to be true
      end
    end
  end

  it "returns the session when opened without a block" do
    create_archive("noblock.zip")

    session = described_class.open(File.join(outdir, "noblock.zip"))
    expect(session.entries.map(&:name)).to include("mydir/sub/b.txt")
    expect(session.read("notes/readme.txt")).to eq("generated\n")
  end

  it "enumerates entries via each_entry" do
    create_archive("each.zip")

    described_class.open(File.join(outdir, "each.zip")) do |archive|
      collected = []
      archive.each_entry { |e| collected << e.name }
      expect(collected).to include("documents/input.txt", "mydir/a.txt")
    end
  end

  it "raises ENOENT for missing entries" do
    create_archive("missing.zip")

    described_class.open(File.join(outdir, "missing.zip")) do |archive|
      expect { archive.read("no-such-entry") }.to raise_error(Errno::ENOENT)
      expect do
        archive.extract("no-such-entry", File.join(outdir, "x"))
      end.to raise_error(Errno::ENOENT)
    end
  end

  it "converts between formats entry by entry (documented pattern)" do
    create_archive("src.zip")

    described_class.open(File.join(outdir, "src.zip")) do |src|
      described_class.create(File.join(outdir, "dst.7z"),
                             format: :seven_zip) do |dst|
        src.entries.each do |entry|
          next if entry.directory?

          dst.add_data(entry.name, src.read(entry.name))
        end
      end
    end

    described_class.open(File.join(outdir, "dst.7z")) do |archive|
      expect(archive.read("mydir/sub/b.txt")).to eq(source)
    end
  end

  describe "passwords" do
    before do
      described_class.create(File.join(outdir, "secure.7z"),
                             format: :seven_zip, password: "s3cret",
                             encrypt_headers: true) do |archive|
        archive.add_data("secret.txt", source)
      end
    end

    it "encrypts and decrypts 7z archives" do
      described_class.open(File.join(outdir, "secure.7z"),
                           password: "s3cret") do |archive|
        expect(archive.read("secret.txt")).to eq(source)
      end
    end

    it "falls back to ENV['OMNIZIP_PASSWORD']" do
      ENV["OMNIZIP_PASSWORD"] = "s3cret"

      described_class.open(File.join(outdir, "secure.7z")) do |archive|
        expect(archive.read("secret.txt")).to eq(source)
      end
    end

    it "never cleanly reads with a wrong password" do
      session = described_class.open(File.join(outdir, "secure.7z"),
                                     password: "wrong")
      clean = begin
        session.read("secret.txt") == source
      rescue StandardError
        false
      end
      expect(clean).to be false
    end

    it "refuses passwords for formats without encryption support" do
      expect do
        described_class.create(File.join(outdir, "x.zip"), password: "p")
      end.to raise_error(Omnizip::UnsupportedFormatError, /no encryption/)
      expect do
        described_class.open(File.join(outdir, "y.tar"), password: "p")
      end.to raise_error(Omnizip::UnsupportedFormatError, /no encryption/)
    end
  end

  it "opens RAR archives with real metadata" do
    fixture = File.expand_path("fixtures/rar/official/normal_method.rar",
                               __dir__)

    described_class.open(fixture) do |archive|
      entry = archive.entries.first
      expect(entry.name).to eq("normal.txt")
      expect(entry.size).to eq(27)
      expect(entry.directory?).to be false
    end

    created = File.join(outdir, "x.rar")
    described_class.create(created) { |a| a.add_data("x", "1") }

    skip "unrar not available" unless Omnizip::Formats::Rar::Decompressor.command_available?

    expect(described_class.open(created) { |a| a.read("x") }).to eq("1")
  end

  it "returns the archive path from create" do
    path = File.join(outdir, "ret.zip")
    expect(described_class.create(path) { |a| a.add_data("x", "1") })
      .to eq(path)
  end
end

RSpec.describe Omnizip::Archive, "RAR creation" do
  it "creates .rar archives through the handler (unrar-verified STORE)" do
    Dir.mktmpdir("omnizip_rar_facade") do |tmp|
      src = File.join(tmp, "a.txt")
      File.binwrite(src, "facade rar content " * 50)
      archive = File.join(tmp, "a.rar")

      Omnizip::Archive.create(archive, format: :rar) do |b|
        b.add_file(src, "a.txt")
        b.add_data("d.txt", "inline data")
      end

      Omnizip::Archive.open(archive) do |a|
        expect(a.entries.map(&:name)).to contain_exactly("a.txt", "d.txt")
      end

      # Gate on the command, not Decompressor.available?: runners can
      # carry the unrar gem without the binary on PATH
      unrar = Omnizip::Formats::Rar::Decompressor.command_path
      if unrar
        Omnizip::Archive.open(archive) do |a|
          expect(a.read("d.txt")).to eq("inline data")
        end
        # Invoke through the resolved path: the binary may live in
        # Program Files rather than on PATH (Windows runners)
        expect(system(unrar, "t", "-idq", archive,
                      out: File::NULL, err: File::NULL)).to be(true)
      end
    end
  end

  it "preserves explicit empty directory entries" do
    Dir.mktmpdir("omnizip_rar_facade_dir") do |tmp|
      empty = File.join(tmp, "emptydir")
      FileUtils.mkdir_p(empty)
      archive = File.join(tmp, "d.rar")

      Omnizip::Archive.create(archive, format: :rar) do |b|
        b.add_directory(empty)
      end

      Omnizip::Archive.open(archive) do |a|
        dir = a.entries.find { |e| e.name == "emptydir" }
        expect(dir).to be_directory
      end
    end
  end
end

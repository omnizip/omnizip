# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tempfile"
require "fileutils"

RSpec.describe "Omnizip.compress_file single-format routing" do
  let(:source) do
    rng = Random.new(21)
    words = %w[alpha beta gamma delta epsilon]
    Array.new(500) { words.sample(rng.rand(2) + 1).join(" ") }.join("\n")
  end
  let(:input) do
    Tempfile.new("omnizip-sf-in").tap do |f|
      f.binmode
      f.write(source)
      f.flush
    end
  end

  let(:outdir) { Dir.mktmpdir("omnizip-sf") }
  after { FileUtils.rm_rf(outdir) }

  def roundtrip_of(ext, outdir)
    path = File.join(outdir, "out#{ext}")
    Omnizip.compress_file(input.path, path)

    out = StringIO.new
    case ext
    when ".gz" then Omnizip::Formats::Gzip.decompress_stream(File.open(path, "rb"), out)
    when ".bz2" then Omnizip::Formats::Bzip2File.decompress_stream(File.open(path, "rb"), out)
    when ".xz" then out << Omnizip::Formats::Xz.decompress(File.binread(path))
    when ".lzma" then Omnizip::Formats::LzmaAlone.decompress_stream(File.open(path, "rb"), out)
    when ".lz" then Omnizip::Formats::Lzip.decompress_stream(File.open(path, "rb"), out)
    end
    [path, out.string]
  end

  [".gz", ".bz2", ".xz", ".lzma", ".lz"].each do |ext|
    it "routes #{ext} to the matching single-file format (not a ZIP)" do
      path, decoded = roundtrip_of(ext, outdir)

      expect(File.binread(path, 2)).not_to eq("PK")
      expect(decoded).to eq(source)
    end
  end

  describe ".decompress_file" do
    it "round-trips every documented extension" do
      [".gz", ".bz2", ".xz", ".lzma", ".lz"].each do |ext|
        compressed = File.join(outdir, "rt#{ext}")
        Omnizip.compress_file(input.path, compressed)

        output = File.join(outdir, "rt#{ext}.out")
        Omnizip.decompress_file(compressed, output)

        expect(File.binread(output)).to eq(source)
      end
    end

    it "raises truthfully for archive extensions" do
      zip_path = File.join(outdir, "plain.zip")
      Omnizip.compress_file(input.path, zip_path)

      expect do
        Omnizip.decompress_file(zip_path, File.join(outdir, "x"))
      end.to raise_error(Omnizip::UnsupportedFormatError, /extract_archive/)
    end

    it "raises for missing input" do
      expect do
        Omnizip.decompress_file(File.join(outdir, "nope.gz"),
                                File.join(outdir, "x"))
      end.to raise_error(Errno::ENOENT)
    end
  end

  it "keeps the ZIP default for unknown extensions" do
    path = File.join(outdir, "out.dat")
    Omnizip.compress_file(input.path, path)

    expect(File.binread(path, 2)).to eq("PK")
  end

  it "produces the documented .lzma container (props + dict + size)" do
    path, = roundtrip_of(".lzma", outdir)
    header = File.binread(path, 13)

    expect(header.getbyte(0)).to eq((((2 * 5) + 0) * 9) + 3)
    expect(header.byteslice(5, 8)).to eq([source.bytesize].pack("Q<"))
  end

  describe "archive extension routing" do
    it "writes a real TAR for .tar outputs" do
      path = File.join(outdir, "out.tar")
      Omnizip.compress_file(input.path, path)

      # POSIX ustar magic at offset 257 — true on every platform.
      expect(File.binread(path, 5, 257)).to eq("ustar")

      if system("tar --version > /dev/null 2>&1")
        listing = `tar -tf #{path}`.strip
        expect(listing).to include(File.basename(input.path))
      end
    end

    it "writes a real 7z for .7z outputs and extracts it back" do
      path = File.join(outdir, "out.7z")
      Omnizip.compress_file(input.path, path)
      expect(File.binread(path, 2)).to eq("7z")

      dest = File.join(outdir, "extracted")
      Omnizip.extract_archive(path, dest)
      expect(File.binread(File.join(dest, File.basename(input.path)))).to eq(source)
    end

    it "raises truthfully for read-only format extensions" do
      [".rar", ".iso", ".cpio"].each do |ext|
        expect do
          Omnizip.compress_file(input.path, File.join(outdir, "out#{ext}"))
        end.to raise_error(Omnizip::UnsupportedFormatError, /read-only/)
      end
    end

    it "compresses directories to .7z and .tar with nested paths" do
      Dir.mktmpdir("omnizip-sf-dir") do |src|
        File.binwrite(File.join(src, "a.txt"), "top-level\n")
        Dir.mkdir(File.join(src, "sub"))
        File.binwrite(File.join(src, "sub", "b.txt"), "nested\n")

        [".7z", ".tar"].each do |ext|
          path = File.join(outdir, "dir#{ext}")
          Omnizip.compress_directory(src, path)

          dest = File.join(outdir, "dir-extract#{ext}")
          Dir.mkdir(dest)
          Omnizip.extract_archive(path, dest)
          expect(File.binread(File.join(dest, "sub", "b.txt"))).to eq("nested\n")
          expect(File.binread(File.join(dest, "a.txt"))).to eq("top-level\n")
        end
      end
    end

    it "lists and reads .7z entries" do
      path = File.join(outdir, "list.7z")
      Omnizip.compress_file(input.path, path)

      expect(Omnizip.list_archive(path)).to eq([File.basename(input.path)])
      details = Omnizip.list_archive(path, details: true)
      expect(details.first[:name]).to eq(File.basename(input.path))
      expect(details.first[:size]).to eq(source.bytesize)
      expect(Omnizip.read_from_archive(path, File.basename(input.path))).to eq(source)
      expect do
        Omnizip.read_from_archive(path, "no-such-entry")
      end.to raise_error(Errno::ENOENT)
    end

    it "names the resolved format in add/remove errors" do
      path = File.join(outdir, "t.7z")
      Omnizip.compress_file(input.path, path)

      expect do
        Omnizip.add_to_archive(path, "x.txt", input.path)
      end.to raise_error(Omnizip::UnsupportedFormatError, /:seven_zip/)
      expect do
        Omnizip.remove_from_archive(path, File.basename(input.path))
      end.to raise_error(Omnizip::UnsupportedFormatError, /:seven_zip/)
    end

    it "keeps the ZIP default for extensionless outputs" do
      path = File.join(outdir, "noext")
      Omnizip.compress_file(input.path, path)

      expect(File.binread(path, 2)).to eq("PK")
    end
  end
end

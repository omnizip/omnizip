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
end

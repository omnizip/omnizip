# frozen_string_literal: true

require "base64"
require "stringio"
require "spec_helper"
require "omnizip/backends"
require "omnizip/implementations/rust"

# Cross-implementation differential for every codec the tier
# accelerates: the Ruby core's own bytes MUST decode identically
# through the Rust backend. Decode is the output-invariant tier
# (auto = rust whenever the cdylib loads), so this gate is the
# contract that makes the swap safe.
RSpec.describe "Rust tier codec coverage" do
  let(:library) { Omnizip::Implementations::Rust::Library }

  def with_backend(mode)
    prev = ENV.fetch("OMNIZIP_BACKEND", nil)
    ENV["OMNIZIP_BACKEND"] = mode
    Omnizip::Implementations::Rust::Library.forget!
    yield
  ensure
    ENV["OMNIZIP_BACKEND"] = prev
    Omnizip::Implementations::Rust::Library.forget!
  end

  def corpus
    @corpus ||= begin
      text = "the quick brown fox jumps over the lazy dog. " * 400
      binary = (0..30_000).map { |i| i % 251 }.pack("C*")
      empty = "".b
      [text, binary, empty]
    end
  end

  def round_trip_via_ruby(decode, stream)
    with_backend("ruby") { decode.call(stream) }
  end

  def round_trip_via_rust(decode, stream)
    with_backend("rust") { decode.call(stream) }
  end

  # good-1-v1.lz from the lzip conformance set (the same fixture
  # omnizip-lzma decodes) — decode-only format.
  LZIP_FIXTURE = Base64.decode64(<<~B64).freeze # rubocop:disable Lint/ConstantDefinitionInBlock
    TFpJUAEMACQZSZhvBRUnJw12eNAqaBcV//91+AAAQ6OiFQ0AAAAAAAAAMgAAAAAAAAA=
  B64

  describe "ppmd7 (param-carrying names)" do
    it "round-trips through the tier where the pure-Ruby core cannot" do
      skip "omnizip-ffi cdylib not built" if library.instance.nil?
      data = "the pure-Ruby core cannot decode its own output " * 8
      s = Omnizip::Algorithms::PPMd7.compress(data, model_order: 6, mem_size: 1 << 24)
      d = Omnizip::Algorithms::PPMd7.decompress(s, model_order: 6, mem_size: 1 << 24)
      expect(d).to eq(data)
      expect(s.bytesize).to be < data.bytesize
    end
  end

  describe "ppmd8 (implemented by the tier)" do
    it "round-trips for the first time (pure-Ruby raises NotImplementedError)" do
      skip "omnizip-ffi cdylib not built" if library.instance.nil?
      data = "the pure-Ruby core never shipped " * 8
      s = Omnizip::Algorithms::PPMd8.compress(data, model_order: 6, mem_size: 1 << 24)
      d = Omnizip::Algorithms::PPMd8.decompress(s, model_order: 6, mem_size: 1 << 24)
      expect(d).to eq(data)
    end
  end

  describe "lzip" do
    it "decodes the conformance member identically on both backends" do
      skip "omnizip-ffi cdylib not built" if library.instance.nil?
      decode = ->(s) { Omnizip::Formats::Xz.decompress(StringIO.new(s)) }
      expect(round_trip_via_ruby(decode, LZIP_FIXTURE))
        .to eq(round_trip_via_rust(decode, LZIP_FIXTURE))
    end
  end

  # A member written by the pre-fix writer (custom header + zlib's own
  # gzip header under it). Standard tools reject these; the Ruby
  # reader must keep decoding them.
  LEGACY_GZ = Base64.decode64(<<~B64).freeze # rubocop:disable Lint/ConstantDefinitionInBlock
    H4sIAAAAAAAAAx+LCAAAAAAAABPLSU1PTK5USMkvTcpJVchITUxJLVIoSKzMyU9MUcgZPpIAkvFC
    e+gAAAA=
  B64

  it "decodes legacy double-header gzip members" do
    out = StringIO.new(+"".b)
    Omnizip::Formats::Gzip.decompress_stream(StringIO.new(LEGACY_GZ), out)
    expect(out.string).to eq("legacy double header payload " * 8)
  end

  it "writes standard gzip members (single header, system-verifiable)" do
    data = "standard member payload " * 20
    out = StringIO.new(+"".b)
    Omnizip::Formats::Gzip.compress_stream(StringIO.new(data), out)
    bytes = out.string
    expect(bytes.byteslice(0, 2)).to eq("\x1F\x8B".b)
    expect(bytes.byteslice(10, 2)).not_to eq("\x1F\x8B".b)
    crc, size = bytes.byteslice(-8, 8).unpack("VV")
    expect(crc).to eq(Zlib.crc32(data))
    expect(size).to eq(data.bytesize)
  end

  shared_examples "an accelerated codec" do |name|
    it "decodes #{name} streams identically on both backends" do
      skip "omnizip-ffi cdylib not built" if library.instance.nil?

      streams.each_with_index do |stream, i|
        ruby = round_trip_via_ruby(decoder, stream)
        rust = round_trip_via_rust(decoder, stream)
        expect(rust.bytesize).to eq(corpus[i].bytesize)
        expect(rust).to eq(ruby)
      end
    end

    it "falls back to Ruby when the dylib is absent" do
      with_backend("ruby") do
        streams.each_with_index do |stream, i|
          expect(decoder.call(stream).bytesize).to eq(corpus[i].bytesize)
        end
      end
    end
  end

  def zstd_stream(data)
    Omnizip::Algorithms::Zstandard.compress(data)
  end

  def deflate_stream(data)
    Omnizip::Algorithms::Deflate.compress(data)
  end

  def zlib_stream(data)
    Omnizip::Algorithms::Deflate64.compress(data)
  end

  def gzip_stream(data)
    out = StringIO.new(+"".b)
    Omnizip::Formats::Gzip.compress_stream(StringIO.new(data), out)
    out.string
  end

  def xz_stream(data)
    Omnizip::Formats::Xz.create(StringIO.new(data))
  end

  def alone_stream(data)
    Omnizip::Algorithms::LZMA.compress(data)
  end

  describe "zstd" do
    let(:streams) { corpus.map { |d| zstd_stream(d) } }
    let(:decoder) do
      ->(stream) { Omnizip::Algorithms::Zstandard.decompress(stream) }
    end
    include_examples "an accelerated codec", "zstd"
  end

  describe "deflate (zlib framing)" do
    let(:streams) { corpus.map { |d| deflate_stream(d) } }
    let(:decoder) do
      ->(stream) { Omnizip::Algorithms::Deflate.decompress(stream) }
    end
    include_examples "an accelerated codec", "deflate"
  end

  describe "zlib (Deflate64 algorithm)" do
    let(:streams) { corpus.map { |d| zlib_stream(d) } }
    let(:decoder) do
      ->(stream) { Omnizip::Algorithms::Deflate64.decompress(stream) }
    end
    include_examples "an accelerated codec", "zlib"
  end

  describe "gzip" do
    let(:streams) { corpus.map { |d| gzip_stream(d) } }
    let(:decoder) do
      lambda do |stream|
        out = StringIO.new(+"".b)
        Omnizip::Formats::Gzip.decompress_stream(StringIO.new(stream), out)
        out.string
      end
    end
    include_examples "an accelerated codec", "gzip"
  end

  describe "xz" do
    let(:streams) { corpus.map { |d| xz_stream(d) } }
    let(:decoder) do
      lambda do |stream|
        Omnizip::Formats::Xz.decompress(StringIO.new(stream))
      end
    end
    include_examples "an accelerated codec", "xz"
  end

  describe "lzma-alone" do
    let(:streams) { corpus.map { |d| alone_stream(d) } }
    let(:decoder) do
      lambda do |stream|
        Omnizip::Formats::Xz.decompress(StringIO.new(stream))
      end
    end
    include_examples "an accelerated codec", "lzma-alone"
  end
end

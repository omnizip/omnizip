# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Formats::Lzip do
  def round_trip(data)
    out = StringIO.new
    out.set_encoding(Encoding::BINARY)
    described_class.compress_stream(StringIO.new(data), out)

    decoded = StringIO.new
    described_class.decompress_stream(StringIO.new(out.string), decoded)
    decoded.string
  end

  it "round-trips small repetitive text" do
    expect(round_trip("hello world " * 100)).to eq("hello world " * 100)
  end

  it "round-trips varied text, empty, and binary inputs" do
    rng = Random.new(5)
    words = %w[alpha beta gamma delta]
    [
      Array.new(1_000) { words.sample(rng.rand(2) + 1).join(" ") }.join("\n"),
      "",
      rng.bytes(300),
    ].each { |data| expect(round_trip(data)).to eq(data) }
  end

  it "writes a version-1 member with the 4 MiB dictionary byte" do
    out = StringIO.new
    described_class.compress_stream(StringIO.new("x"), out)

    expect(out.string.byteslice(0, 6)).to eq("LZIP".b + [1, 22].pack("CC"))
  end
end

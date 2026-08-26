# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Formats::LzmaAlone do
  def round_trip(data)
    out = StringIO.new
    out.set_encoding(Encoding::BINARY)
    described_class.compress_stream(StringIO.new(data), out)

    decoded = StringIO.new
    described_class.decompress_stream(StringIO.new(out.string), decoded)
    decoded.string
  end

  it "round-trips text, empty, and binary inputs" do
    rng = Random.new(9)
    [
      "the quick brown fox " * 200,
      "",
      rng.bytes(400),
    ].each { |data| expect(round_trip(data)).to eq(data) }
  end

  it "writes the props/dict/size header" do
    out = StringIO.new
    out.set_encoding(Encoding::BINARY)
    described_class.compress_stream(StringIO.new("abc"), out)

    header = out.string.byteslice(0, 13)
    expect(header.getbyte(0)).to eq((((2 * 5) + 0) * 9) + 3)
    expect(header.byteslice(5, 8)).to eq([3].pack("Q<"))
  end
end

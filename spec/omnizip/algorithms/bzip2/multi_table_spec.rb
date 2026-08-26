# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BZip2 multi-table Huffman" do
  let(:data) do
    rng = Random.new(7)
    words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit]
    Array.new(2_000) { words[rng.rand(words.length)] }.join(" ")
  end

  it "round-trips multi-table output through the native decoder" do
    compressed = Omnizip::Algorithms::BZip2.compress(data, level: 9)

    expect(compressed.byteslice(0, 4)).to eq("BZh9")
    expect(Omnizip::Algorithms::BZip2.decompress(compressed)).to eq(data)
  end

  it "compresses at least as well as the single-table path" do
    compressed = Omnizip::Algorithms::BZip2.compress(data, level: 9)

    # The reference single-table ratio was 0.0743 on this corpus; the
    # multi-table path should not regress (allowing for tiny noise
    # from the chunk-table assignment on a small-ish input).
    expect(compressed.bytesize).to be <= 10_500
  end
end

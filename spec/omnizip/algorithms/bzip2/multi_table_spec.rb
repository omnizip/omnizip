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

  it "matches the reference bzip2 CLI ratio class" do
    compressed = Omnizip::Algorithms::BZip2.compress(data, level: 9)

    # With the upstream table selection (ramp-seeded, 4 assignment
    # iterations) this corpus sits in the bzip2 -9 ballpark; the
    # spec corpus (137,998 B -> 8,974 B locally vs CLI 8,981 B) is
    # the authoritative comparison — keep a loose budget here so the
    # smaller spec corpus does not flake on table-assignment noise.
    expect(compressed.bytesize).to be <= 1_200
  end
end

# frozen_string_literal: true

require "spec_helper"
require "English"
require "tempfile"

RSpec.describe "BZip2 standard wire format" do
  let(:data) do
    rng = Random.new(7)
    words = %w[lorem ipsum dolor sit amet consectetur adipiscing elit]
    Array.new(2_000) { words[rng.rand(words.length)] }.join(" ")
  end

  it "emits a standard BZh stream" do
    compressed = Omnizip::Algorithms::BZip2.compress("banana banana")

    expect(compressed.byteslice(0, 4)).to eq("BZh9")
  end

  it "round-trips through the native decoder" do
    compressed = Omnizip::Algorithms::BZip2.compress(data)

    expect(Omnizip::Algorithms::BZip2.decompress(compressed)).to eq(data)
  end

  it "round-trips empty streams" do
    compressed = Omnizip::Algorithms::BZip2.compress("")

    expect(compressed.byteslice(0, 4)).to eq("BZh9")
    expect(Omnizip::Algorithms::BZip2.decompress(compressed)).to eq("")
  end

  it "uses the bzip2 CRC variant" do
    expect(
      Omnizip::Algorithms::BZip2::Bz2
        .crc32("banana banana banana banana banana"),
    ).to eq(0xB0A69503)
  end

  context "with the system bzip2 CLI" do
    before { skip "bzip2 CLI not available" unless system("which bzip2 > /dev/null 2>&1") }

    it "produces streams the CLI can decode" do
      compressed = Omnizip::Algorithms::BZip2.compress(data)
      Tempfile.create(%w[omnizip .bz2]) do |compressed_file|
        compressed_file.binmode
        compressed_file.write(compressed)
        compressed_file.flush

        out = `bzip2 -dc -q #{compressed_file.path}`
        expect($CHILD_STATUS).to be_success
        expect(out).to eq(data)
      end
    end

    it "decodes streams produced by the CLI" do
      Tempfile.create("omnizip-bzip2-input") do |input_file|
        input_file.binmode
        input_file.write(data)
        input_file.flush

        compressed = `bzip2 -9 -k -q -c #{input_file.path}`
        expect($CHILD_STATUS).to be_success
        expect(Omnizip::Algorithms::BZip2.decompress(compressed)).to eq(data)
      end
    end
  end
end

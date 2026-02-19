# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::Zstandard do
  let(:algorithm) { described_class.new }
  let(:test_data) { "Hello, World! " * 100 }

  describe ".metadata" do
    it "returns algorithm metadata" do
      metadata = described_class.metadata
      expect(metadata.name).to eq("zstandard")
      expect(metadata.description).to include("Zstandard")
      expect(metadata.version).to eq("1.0.0")
    end
  end

  describe "#compress and #decompress" do
    context "when zstd-ruby gem is available" do
      it "compresses and decompresses data correctly" do
        skip "Pure Ruby Zstandard deferred to v0.4.0 (RFC 8878 implementation required)"

        input = StringIO.new(test_data)
        compressed = StringIO.new

        algorithm.compress(input, compressed)

        compressed.rewind
        decompressed = StringIO.new
        algorithm.decompress(compressed, decompressed)

        expect(decompressed.string).to eq(test_data)
      end

      it "achieves compression on repetitive data" do
        skip "Pure Ruby Zstandard deferred to v0.4.0 (RFC 8878 implementation required)"

        input = StringIO.new(test_data)
        compressed = StringIO.new

        algorithm.compress(input, compressed)

        expect(compressed.string.bytesize).to be < test_data.bytesize
      end
    end
  end

  describe "algorithm registration" do
    it "registers the algorithm with AlgorithmRegistry" do
      expect(Omnizip::AlgorithmRegistry.registered?(:zstandard)).to be true
      expect(Omnizip::AlgorithmRegistry.get(:zstandard))
        .to eq(described_class)
    end
  end
end

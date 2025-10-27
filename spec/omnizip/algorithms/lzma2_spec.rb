# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA2 do
  describe ".metadata" do
    let(:metadata) { described_class.metadata }

    it "returns algorithm metadata" do
      expect(metadata).to be_a(Omnizip::Models::AlgorithmMetadata)
    end

    it "has correct name" do
      expect(metadata.name).to eq("lzma2")
    end

    it "has description" do
      expect(metadata.description).to include("LZMA2")
      expect(metadata.description).to include("chunking")
    end

    it "has version" do
      expect(metadata.version).to eq("1.0.0")
    end
  end

  describe "registration" do
    it "is registered in algorithm registry" do
      algo = Omnizip::AlgorithmRegistry.get(:lzma2)
      expect(algo).to eq(described_class)
    end
  end

  describe "#compress and #decompress" do
    let(:algorithm) { described_class.new }
    let(:input_data) { "Hello, LZMA2 World!" }
    let(:input_stream) { StringIO.new(input_data) }
    let(:output_stream) { StringIO.new }

    it "compresses data" do
      algorithm.compress(input_stream, output_stream)
      expect(output_stream.string).not_to be_empty
      expect(output_stream.string.bytesize).to be > 0
    end

    it "decompresses to original data" do
      algorithm.compress(input_stream, output_stream)

      compressed = output_stream.string
      decompressed_output = StringIO.new

      algorithm.decompress(StringIO.new(compressed), decompressed_output)
      expect(decompressed_output.string).to eq(input_data)
    end
  end
end

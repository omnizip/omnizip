# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Models::AlgorithmMetadata do
  describe "initialization" do
    it "creates instance with all attributes" do
      metadata = described_class.new(
        name: "lzma",
        description: "LZMA compression algorithm",
        version: "1.0.0",
        author: "Igor Pavlov",
        max_compression_level: 9,
        min_compression_level: 0,
        default_compression_level: 5,
        supports_streaming: true,
        supports_multithreading: false
      )

      expect(metadata.name).to eq("lzma")
      expect(metadata.description).to eq("LZMA compression algorithm")
      expect(metadata.version).to eq("1.0.0")
      expect(metadata.author).to eq("Igor Pavlov")
      expect(metadata.max_compression_level).to eq(9)
      expect(metadata.min_compression_level).to eq(0)
      expect(metadata.default_compression_level).to eq(5)
      expect(metadata.supports_streaming).to be true
      expect(metadata.supports_multithreading).to be false
    end

    it "uses default values for boolean attributes" do
      metadata = described_class.new(name: "test")

      expect(metadata.supports_streaming).to be false
      expect(metadata.supports_multithreading).to be false
    end
  end

  describe "JSON serialization" do
    let(:metadata) do
      described_class.new(
        name: "lzma",
        description: "LZMA compression",
        version: "1.0",
        author: "Test",
        max_compression_level: 9,
        min_compression_level: 0,
        default_compression_level: 5,
        supports_streaming: true,
        supports_multithreading: false
      )
    end

    it "serializes to JSON" do
      json = metadata.to_json

      expect(json).to include('"name":"lzma"')
      expect(json).to include('"description":"LZMA compression"')
      expect(json).to include('"supports_streaming":true')
    end

    it "deserializes from JSON" do
      json = metadata.to_json
      restored = described_class.from_json(json)

      expect(restored.name).to eq(metadata.name)
      expect(restored.description).to eq(metadata.description)
      expect(restored.supports_streaming).to eq(metadata.supports_streaming)
    end
  end
end

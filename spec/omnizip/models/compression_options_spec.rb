# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Models::CompressionOptions do
  describe "initialization" do
    it "creates instance with default values" do
      options = described_class.new

      expect(options.level).to eq(5)
      expect(options.num_threads).to eq(1)
      expect(options.solid).to be false
      expect(options.buffer_size).to eq(65_536)
    end

    it "creates instance with custom values" do
      options = described_class.new(
        level: 9,
        dictionary_size: 16_777_216,
        num_fast_bytes: 273,
        match_finder: "bt4",
        num_threads: 4,
        solid: true,
        buffer_size: 131_072,
      )

      expect(options.level).to eq(9)
      expect(options.dictionary_size).to eq(16_777_216)
      expect(options.num_fast_bytes).to eq(273)
      expect(options.match_finder).to eq("bt4")
      expect(options.num_threads).to eq(4)
      expect(options.solid).to be true
      expect(options.buffer_size).to eq(131_072)
    end
  end

  describe "JSON serialization" do
    let(:options) do
      described_class.new(
        level: 7,
        dictionary_size: 8_388_608,
        num_threads: 2,
      )
    end

    it "serializes to JSON" do
      json = options.to_json

      expect(json).to include('"level":7')
      expect(json).to include('"dictionary_size":8388608')
      expect(json).to include('"num_threads":2')
    end

    it "deserializes from JSON" do
      json = options.to_json
      restored = described_class.from_json(json)

      expect(restored.level).to eq(options.level)
      expect(restored.dictionary_size).to eq(options.dictionary_size)
      expect(restored.num_threads).to eq(options.num_threads)
    end
  end
end

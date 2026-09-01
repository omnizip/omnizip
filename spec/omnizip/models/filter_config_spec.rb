# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Models::FilterConfig do
  let(:config) { described_class.new(name: :bcj_x86, architecture: :x86) }

  describe "#initialize" do
    it "stores name as symbol" do
      expect(config.name_sym).to eq(:bcj_x86)
    end

    it "stores properties" do
      config.properties = "\x00".b
      expect(config.properties).to eq("\x00".b)
    end

    it "stores architecture" do
      expect(config.architecture).to eq(:x86)
    end

    it "defaults properties to empty string" do
      expect(described_class.new.properties).to eq("".b)
    end
  end

  describe "#name_sym" do
    it "returns filter name as symbol" do
      expect(config.name_sym).to eq(:bcj_x86)
    end
  end

  describe "#name=" do
    it "updates name and name_sym" do
      config.name = :delta
      expect(config.name_sym).to eq(:delta)
    end
  end

  describe "#bcj?" do
    it "returns true for BCJ filters" do
      expect(config.bcj?).to be true
    end

    it "returns false for non-BCJ filters" do
      delta_config = described_class.new(name: :delta)
      expect(delta_config.bcj?).to be false
    end
  end

  describe "#delta?" do
    it "returns true for delta filter" do
      delta_config = described_class.new(name: :delta)
      expect(delta_config.delta?).to be true
    end

    it "returns false for non-delta filters" do
      expect(config.delta?).to be false
    end
  end

  describe "#to_hash" do
    it "serializes name, architecture, and properties" do
      config.properties = "\x01\x02".b
      hash = config.to_hash
      expect(hash["name"]).to eq(:bcj_x86)
      expect(hash["architecture"]).to eq(:x86)
      expect(hash["properties"]).to eq("\x01\x02".b)
    end

    it "defaults properties to an empty binary string" do
      # lutaml-model 0.8.x omits empty-string values from to_hash;
      # the default lives on the reader.
      expect(config.properties).to eq("".b)
    end
  end

  describe "#validate!" do
    it "passes with valid data" do
      # Mock the FilterRegistry to return true for registered?
      allow(Omnizip::FilterRegistry).to receive(:registered?).with(:bcj_x86).and_return(true)

      expect { config.validate! }.not_to raise_error
    end

    it "raises when name is nil" do
      nil_name_config = described_class.new
      expect do
        nil_name_config.validate!
      end.to raise_error(ArgumentError, /name is required/)
    end
  end
end

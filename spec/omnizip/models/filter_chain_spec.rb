# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Models::FilterChain do
  let(:chain) { described_class.new(format: :xz) }

  describe "#initialize" do
    it "sets format" do
      expect(chain.format).to eq(:xz)
    end

    it "defaults format to xz" do
      expect(described_class.new.format).to eq(:xz)
    end

    it "initializes with empty filters" do
      expect(chain.filters).to eq([])
    end
  end

  describe "#add_filter" do
    it "adds filter to chain" do
      chain.add_filter(name: :"bcj-x86", architecture: :x86)
      expect(chain.size).to eq(1)
    end

    it "returns self for chaining" do
      result = chain.add_filter(name: :"bcj-x86", architecture: :x86)
      expect(result).to eq(chain)
    end
  end

  describe "#max_filters" do
    it "returns 4 for XZ format" do
      expect(chain.max_filters).to eq(4)
    end

    it "returns 4 for 7z format" do
      chain_7z = described_class.new(format: :seven_zip)
      expect(chain_7z.max_filters).to eq(4)
    end
  end

  describe "#validate!" do
    it "passes with valid filters" do
      chain.add_filter(name: :"bcj-x86", architecture: :x86)
      expect { chain.validate! }.not_to raise_error
    end

    it "raises when too many filters" do
      5.times { chain.add_filter(name: :"bcj-x86", architecture: :x86) }
      expect do
        chain.validate!
      end.to raise_error(ArgumentError, /Too many filters/)
    end
  end

  describe "#encode_all and #decode_all" do
    before do
      chain.add_filter(name: :"bcj-x86", architecture: :x86)
    end

    it "roundtrips data correctly" do
      original = "test data"
      encoded = chain.encode_all(original, 0)
      decoded = chain.decode_all(encoded, 0)
      expect(decoded).to eq(original)
    end

    it "handles empty filter chain" do
      empty_chain = described_class.new(format: :xz)
      data = "test"
      expect(empty_chain.encode_all(data)).to eq(data)
      expect(empty_chain.decode_all(data)).to eq(data)
    end
  end

  describe "#filter_ids" do
    it "returns filter IDs for current format" do
      # Use the newer BCJ filter which has id_for_format support
      chain.add_filter(name: :bcj, architecture: :x86)
      expect(chain.filter_ids).to be_a(Array)
      expect(chain.filter_ids.first).to be_a(Integer)
    end
  end

  describe "#empty?" do
    it "returns true when no filters" do
      expect(chain.empty?).to be true
    end

    it "returns false when filters added" do
      chain.add_filter(name: :"bcj-x86", architecture: :x86)
      expect(chain.empty?).to be false
    end
  end
end

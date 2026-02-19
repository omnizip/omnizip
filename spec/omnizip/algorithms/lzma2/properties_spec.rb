# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA2::Properties do
  describe "#initialize" do
    it "accepts valid dictionary size" do
      props = described_class.new(1 << 20)
      expect(props.dict_size).to eq(1 << 20)
    end

    it "raises error for too small dictionary size" do
      expect do
        described_class.new(1 << 10)
      end.to raise_error(ArgumentError, /must be between/)
    end

    it "raises error for too large dictionary size" do
      expect do
        described_class.new(1 << 31)
      end.to raise_error(ArgumentError, /must be between/)
    end
  end

  describe ".from_byte" do
    it "creates properties from valid property byte" do
      props = described_class.from_byte(10)
      expect(props).to be_a(described_class)
    end

    it "raises error for invalid property byte" do
      expect do
        described_class.from_byte(50)
      end.to raise_error(ArgumentError, /must be between/)
    end
  end

  describe ".decode_dict_size" do
    it "decodes prop 0 to 4KB" do
      size = described_class.decode_dict_size(0)
      # XZ Utils formula: dict_size = (2 | (props & 1)) << (props / 2 + 11)
      # For props=0: (2 | 0) << (0 + 11) = 2 << 11 = 4096 = 4KB
      expect(size).to eq(4096)
    end

    it "decodes prop 1 to 6KB" do
      size = described_class.decode_dict_size(1)
      # For props=1: (2 | 1) << (0 + 11) = 3 << 11 = 6144 ≈ 6KB
      expect(size).to eq(6144)
    end

    it "decodes prop 2 to 8KB" do
      size = described_class.decode_dict_size(2)
      # For props=2: (2 | 0) << (1 + 11) = 2 << 12 = 8192 = 8KB
      expect(size).to eq(8192)
    end

    it "handles larger prop values correctly" do
      size = described_class.decode_dict_size(20)
      expect(size).to be > (1 << 20)
    end
  end

  describe "#encode_dict_size" do
    it "encodes dictionary size to property byte" do
      props = described_class.new(1 << 20)
      expect(props.prop_byte).to be_between(0, 40)
    end

    it "finds smallest prop for requested size" do
      props = described_class.new(1 << 12)
      decoded_size = described_class.decode_dict_size(props.prop_byte)
      expect(decoded_size).to be >= (1 << 12)
    end
  end

  describe "#actual_dict_size" do
    it "returns decoded dictionary size" do
      props = described_class.new(1 << 20)
      actual = props.actual_dict_size
      expect(actual).to be >= (1 << 20)
    end

    it "matches decode_dict_size result" do
      props = described_class.new(1 << 23)
      expected = described_class.decode_dict_size(props.prop_byte)
      expect(props.actual_dict_size).to eq(expected)
    end
  end
end

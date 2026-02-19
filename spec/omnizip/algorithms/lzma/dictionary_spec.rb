require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA::Dictionary do
  describe "#initialize" do
    it "initializes with given size" do
      dict = described_class.new(4096)
      expect(dict.size).to eq(4096)
    end

    it "starts empty" do
      dict = described_class.new(4096)
      expect(dict.buffer).to be_empty
    end
  end

  describe "#append" do
    it "adds bytes to buffer" do
      dict = described_class.new(100)
      dict.append("Hello")
      expect(dict.buffer).to eq("Hello")
    end

    it "tracks position" do
      dict = described_class.new(100)
      dict.append("Hi")
      expect(dict.position).to eq(2)
    end

    it "trims when exceeding size" do
      dict = described_class.new(5)
      dict.append("HelloWorld")
      expect(dict.buffer.bytesize).to eq(5)
      expect(dict.buffer).to eq("World")
    end
  end

  describe "#read_bytes" do
    it "reads bytes at distance back" do
      dict = described_class.new(100)
      dict.append("ABCDEFGH")
      result = dict.read_bytes(3, 3)
      expect(result).to eq("FGH")
    end

    it "raises on invalid distance" do
      dict = described_class.new(100)
      dict.append("Hello")
      expect { dict.read_bytes(10, 1) }.to raise_error(/Invalid distance/)
    end
  end

  describe "#get_byte" do
    it "gets single byte at distance" do
      dict = described_class.new(100)
      dict.append("ABC")
      expect(dict.get_byte(1)).to eq(?C.ord)
    end
  end

  describe "#reset!" do
    it "clears buffer and position" do
      dict = described_class.new(100)
      dict.append("Hello")
      dict.reset!
      expect(dict.buffer).to be_empty
      expect(dict.position).to eq(0)
    end
  end

  describe "#clone" do
    it "creates independent copy" do
      dict1 = described_class.new(100)
      dict1.append("Hello")
      dict2 = dict1.clone
      dict2.append("World")
      expect(dict1.buffer).to eq("Hello")
      expect(dict2.buffer).to eq("HelloWorld")
    end
  end
end

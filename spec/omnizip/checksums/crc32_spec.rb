# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Checksums::Crc32 do
  describe ".calculate" do
    it "calculates CRC32 for empty data" do
      result = described_class.calculate("")
      expect(result).to eq(0x00000000)
    end

    it "calculates CRC32 for single character" do
      result = described_class.calculate("a")
      expect(result).to eq(0xE8B7BE43)
    end

    it "calculates CRC32 for 'abc'" do
      result = described_class.calculate("abc")
      expect(result).to eq(0x352441C2)
    end

    it "calculates CRC32 for 'message digest'" do
      result = described_class.calculate("message digest")
      expect(result).to eq(0x20159D7F)
    end

    it "calculates CRC32 for '123456789'" do
      result = described_class.calculate("123456789")
      expect(result).to eq(0xCBF43926)
    end

    it "handles binary data correctly" do
      binary_data = "\x00\x01\x02\x03\xFF".b
      result = described_class.calculate(binary_data)
      expect(result).to be_a(Integer)
      expect(result).to be >= 0
      expect(result).to be <= 0xFFFFFFFF
    end
  end

  describe "#initialize" do
    it "creates a new CRC32 instance with initial value" do
      crc = described_class.new
      expect(crc.value).to eq(0xFFFFFFFF)
    end
  end

  describe "#update" do
    let(:crc) { described_class.new }

    it "updates CRC value with data" do
      initial_value = crc.value
      crc.update("test")
      expect(crc.value).not_to eq(initial_value)
    end

    it "returns self for method chaining" do
      result = crc.update("test")
      expect(result).to be(crc)
    end

    it "handles incremental updates correctly" do
      crc1 = described_class.new
      crc1.update("Hello, ")
      crc1.update("world!")
      result1 = crc1.finalize

      crc2 = described_class.new
      crc2.update("Hello, world!")
      result2 = crc2.finalize

      expect(result1).to eq(result2)
    end

    it "processes each byte correctly" do
      crc1 = described_class.new
      crc1.update("a")
      crc1.update("b")
      crc1.update("c")
      result1 = crc1.finalize

      result2 = described_class.calculate("abc")

      expect(result1).to eq(result2)
    end

    it "handles empty string update" do
      crc.update("")
      expect(crc.value).to eq(0xFFFFFFFF)
    end
  end

  describe "#reset" do
    let(:crc) { described_class.new }

    it "resets CRC to initial value" do
      crc.update("test data")
      crc.reset
      expect(crc.value).to eq(0xFFFFFFFF)
    end

    it "returns self for method chaining" do
      crc.update("test")
      result = crc.reset
      expect(result).to be(crc)
    end

    it "allows reuse after reset" do
      crc.update("first")
      first_result = crc.finalize

      crc.reset
      crc.update("first")
      second_result = crc.finalize

      expect(first_result).to eq(second_result)
    end
  end

  describe "#finalize" do
    it "applies final XOR to produce correct result" do
      crc = described_class.new
      crc.update("abc")
      result = crc.finalize

      expect(result).to eq(0x352441C2)
    end

    it "does not modify internal state" do
      crc = described_class.new
      crc.update("test")
      value_before = crc.value

      crc.finalize

      expect(crc.value).to eq(value_before)
    end
  end

  describe "large data handling" do
    it "handles data larger than 1KB" do
      large_data = "x" * 2048
      result = described_class.calculate(large_data)

      expect(result).to be_a(Integer)
      expect(result).to be >= 0
      expect(result).to be <= 0xFFFFFFFF
    end

    it "produces consistent results for large data" do
      large_data = "test" * 1000

      result1 = described_class.calculate(large_data)
      result2 = described_class.calculate(large_data)

      expect(result1).to eq(result2)
    end

    it "handles incremental processing of large data" do
      chunk_size = 256
      large_data = "data" * 1000

      crc_incremental = described_class.new
      large_data.chars.each_slice(chunk_size) do |chunk|
        crc_incremental.update(chunk.join)
      end
      result1 = crc_incremental.finalize

      result2 = described_class.calculate(large_data)

      expect(result1).to eq(result2)
    end
  end

  describe "lookup table" do
    it "has pre-computed lookup table" do
      expect(described_class::TABLE).to be_frozen
      expect(described_class::TABLE.size).to eq(256)
    end

    it "has valid table entries" do
      described_class::TABLE.each do |entry|
        expect(entry).to be_a(Integer)
        expect(entry).to be >= 0
        expect(entry).to be <= 0xFFFFFFFF
      end
    end

    it "generates consistent table" do
      table1 = described_class.lookup_table
      table2 = described_class.generate_table(
        described_class::POLYNOMIAL, 32
      )

      expect(table1).to eq(table2)
    end
  end

  describe "polynomial constants" do
    it "uses IEEE 802.3 polynomial" do
      expect(described_class::POLYNOMIAL).to eq(0xEDB88320)
    end

    it "uses correct 32-bit mask" do
      expect(described_class::MASK_32).to eq(0xFFFFFFFF)
    end
  end

  describe "edge cases" do
    it "handles all zero bytes" do
      data = "\x00\x00\x00\x00".b
      result = described_class.calculate(data)

      expect(result).to be_a(Integer)
    end

    it "handles all 0xFF bytes" do
      data = "\xFF\xFF\xFF\xFF".b
      result = described_class.calculate(data)

      expect(result).to be_a(Integer)
    end

    it "handles single byte values 0-255" do
      (0..255).each do |byte_value|
        data = byte_value.chr(Encoding::BINARY)
        result = described_class.calculate(data)

        expect(result).to be >= 0
        expect(result).to be <= 0xFFFFFFFF
      end
    end
  end
end

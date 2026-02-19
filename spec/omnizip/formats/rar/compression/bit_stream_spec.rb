# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Compression::BitStream do
  describe "#initialize" do
    it "initializes in read mode by default" do
      io = StringIO.new("\xFF")
      stream = described_class.new(io)

      expect { stream.read_bit }.not_to raise_error
    end

    it "initializes in write mode when specified" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      expect { stream.write_bit(1) }.not_to raise_error
    end
  end

  describe "#read_bit" do
    it "reads individual bits correctly" do
      # 0b10110101 = 0xB5
      io = StringIO.new("\xB5")
      stream = described_class.new(io, :read)

      expect(stream.read_bit).to eq(1)
      expect(stream.read_bit).to eq(0)
      expect(stream.read_bit).to eq(1)
      expect(stream.read_bit).to eq(1)
      expect(stream.read_bit).to eq(0)
      expect(stream.read_bit).to eq(1)
      expect(stream.read_bit).to eq(0)
      expect(stream.read_bit).to eq(1)
    end

    it "reads across byte boundaries" do
      # 0xAB = 0b10101011, 0xCD = 0b11001101
      io = StringIO.new("\xAB\xCD")
      stream = described_class.new(io, :read)

      # Read 8 bits from first byte
      8.times { stream.read_bit }

      # Read from second byte
      expect(stream.read_bit).to eq(1)
      expect(stream.read_bit).to eq(1)
    end

    it "raises error in write mode" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      expect { stream.read_bit }.to raise_error(ArgumentError, /read mode/)
    end

    it "raises error on EOF" do
      io = StringIO.new("")
      stream = described_class.new(io, :read)

      expect { stream.read_bit }.to raise_error(EOFError)
    end
  end

  describe "#read_bits" do
    it "reads multiple bits as integer" do
      # 0b10110101 = 0xB5
      io = StringIO.new("\xB5")
      stream = described_class.new(io, :read)

      # Read 4 bits: 1011 = 11
      expect(stream.read_bits(4)).to eq(11)
      # Read 4 bits: 0101 = 5
      expect(stream.read_bits(4)).to eq(5)
    end

    it "reads bits across byte boundaries" do
      # 0xFF = 0b11111111, 0x00 = 0b00000000
      io = StringIO.new("\xFF\x00")
      stream = described_class.new(io, :read)

      # Read 12 bits: 111111110000 = 4080
      expect(stream.read_bits(12)).to eq(4080)
    end

    it "validates count range" do
      io = StringIO.new("\xFF")
      stream = described_class.new(io, :read)

      expect { stream.read_bits(0) }.to raise_error(ArgumentError, /1-32/)
      expect { stream.read_bits(33) }.to raise_error(ArgumentError, /1-32/)
    end
  end

  describe "#write_bit" do
    it "writes individual bits correctly" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Write 0b10110101 = 0xB5
      stream.write_bit(1)
      stream.write_bit(0)
      stream.write_bit(1)
      stream.write_bit(1)
      stream.write_bit(0)
      stream.write_bit(1)
      stream.write_bit(0)
      stream.write_bit(1)
      stream.flush

      expect(io.string).to eq("\xB5".b)
    end

    it "buffers bits until byte complete" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Write 4 bits (no flush yet)
      4.times { stream.write_bit(1) }
      expect(io.string).to eq("")

      # Write 4 more bits (triggers flush)
      4.times { stream.write_bit(0) }
      expect(io.string).to eq("\xF0".b)
    end

    it "raises error in read mode" do
      io = StringIO.new("\xFF")
      stream = described_class.new(io, :read)

      expect { stream.write_bit(1) }.to raise_error(ArgumentError, /write mode/)
    end
  end

  describe "#write_bits" do
    it "writes multiple bits from integer" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Write 11 (0b1011) as 4 bits, then 5 (0b0101) as 4 bits
      stream.write_bits(11, 4)
      stream.write_bits(5, 4)
      stream.flush

      # Result: 0b10110101 = 0xB5
      expect(io.string).to eq("\xB5".b)
    end

    it "writes bits across byte boundaries" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Write 4080 (0b111111110000) as 12 bits
      stream.write_bits(4080, 12)
      stream.flush

      # Result: 0xFF 0b0000xxxx (padded)
      bytes = io.string.bytes
      expect(bytes[0]).to eq(0xFF)
      expect(bytes[1] & 0xF0).to eq(0x00)
    end

    it "validates count range" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      expect { stream.write_bits(1, 0) }.to raise_error(ArgumentError, /1-32/)
      expect { stream.write_bits(1, 33) }.to raise_error(ArgumentError, /1-32/)
    end
  end

  describe "#align_to_byte" do
    it "discards remaining bits in buffer" do
      # 0xFF 0xAA
      io = StringIO.new("\xFF\xAA")
      stream = described_class.new(io, :read)

      # Read 4 bits from first byte
      stream.read_bits(4)

      # Align to byte boundary (discards remaining 4 bits)
      stream.align_to_byte

      # Next read should be from second byte
      expect(stream.read_bits(8)).to eq(0xAA)
    end

    it "does nothing if already aligned" do
      io = StringIO.new("\xFF\xAA")
      stream = described_class.new(io, :read)

      # Read full byte
      stream.read_bits(8)

      # Already aligned
      stream.align_to_byte

      # Next read should be from second byte
      expect(stream.read_bits(8)).to eq(0xAA)
    end
  end

  describe "#flush" do
    it "writes remaining bits with padding" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Write 4 bits
      stream.write_bits(0b1011, 4)
      stream.flush

      # Result: 0b10110000 (padded with zeros)
      expect(io.string).to eq("\xB0".b)
    end

    it "does nothing if buffer is empty" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Flush with no data
      stream.flush

      expect(io.string).to eq("")
    end

    it "does nothing if already flushed" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))
      stream = described_class.new(io, :write)

      # Write full byte
      stream.write_bits(0xFF, 8)

      # Already flushed automatically
      stream.flush

      expect(io.string).to eq("\xFF".b)
    end
  end

  describe "#eof?" do
    it "returns true when at end of stream" do
      io = StringIO.new("")
      stream = described_class.new(io, :read)

      expect(stream.eof?).to eq(true)
    end

    it "returns false when data available" do
      io = StringIO.new("\xFF")
      stream = described_class.new(io, :read)

      expect(stream.eof?).to eq(false)
    end

    it "returns false when bits remain in buffer" do
      io = StringIO.new("\xFF")
      stream = described_class.new(io, :read)

      # Read 4 bits (4 remain in buffer)
      stream.read_bits(4)

      expect(stream.eof?).to eq(false)
    end
  end

  describe "round-trip" do
    it "preserves data through write and read" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))

      # Write data
      writer = described_class.new(io, :write)
      writer.write_bits(0xAB, 8)
      writer.write_bits(0xCD, 8)
      writer.flush

      # Read back
      io.rewind
      reader = described_class.new(io, :read)

      expect(reader.read_bits(8)).to eq(0xAB)
      expect(reader.read_bits(8)).to eq(0xCD)
    end

    it "handles partial byte writes" do
      io = StringIO.new(String.new(encoding: Encoding::BINARY))

      # Write 12 bits
      writer = described_class.new(io, :write)
      writer.write_bits(0xABC, 12)
      writer.flush

      # Read back
      io.rewind
      reader = described_class.new(io, :read)

      # Read 12 bits (remaining 4 are padding)
      expect(reader.read_bits(12)).to eq(0xABC)
    end
  end
end

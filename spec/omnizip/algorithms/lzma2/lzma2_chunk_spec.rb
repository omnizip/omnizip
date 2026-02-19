# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::LZMA2::LZMA2Chunk do
  describe "#end_chunk" do
    it "creates end marker chunk" do
      chunk = described_class.end_chunk
      expect(chunk.to_bytes).to eq("\x00")
    end
  end

  describe "uncompressed chunk" do
    it "serializes correctly" do
      chunk = described_class.new(
        chunk_type: :uncompressed,
        uncompressed_data: "Hello",
        compressed_data: "",
        need_dict_reset: true,
        need_state_reset: false,
        need_props: false,
      )

      bytes = chunk.to_bytes
      expect(bytes.getbyte(0)).to eq(0x01)  # Dict reset
      expect(bytes.getbyte(1)).to eq(0x00)  # Size high byte
      expect(bytes.getbyte(2)).to eq(0x04)  # Size low byte (5-1=4)
    end
  end

  describe "compressed chunk" do
    it "serializes with properties" do
      chunk = described_class.new(
        chunk_type: :compressed,
        uncompressed_data: "Test",
        compressed_data: "\x00\x01",
        properties: 0x5D, # lc=3, lp=0, pb=2
        need_dict_reset: true,
        need_state_reset: false,
        need_props: true,
      )

      bytes = chunk.to_bytes
      expect(bytes.getbyte(0) & 0x80).to eq(0x80)  # Compressed flag
      expect(bytes.getbyte(0) & 0x60).to eq(0x60)  # Dict reset
    end
  end

  describe "validation" do
    it "raises error for invalid chunk_type" do
      expect do
        described_class.new(
          chunk_type: :invalid_type,
          uncompressed_data: "",
          compressed_data: "",
          need_dict_reset: false,
          need_state_reset: false,
          need_props: false,
        )
      end.to raise_error(ArgumentError, /Invalid chunk_type/)
    end
  end
end
